defmodule Unlock.Controller do
  @moduledoc """
  The main controller for proxying, focusing on simplicity and runtime control.

  This currently implements an in-RAM (Cachex) loading of the resource, with a reduced
  set of headers that we will improve over time.

  Future evolutions will very likely support FTP proxying, disk caching, custom headers.

  Useful resources for later maintenance:
  - https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
  - https://www.mnot.net/blog/2011/07/11/what_proxies_must_do
  """

  use Phoenix.Controller
  require Logger

  defmodule ProxyCacheEntry do
    @moduledoc """
    The structure we use to persist HTTP responses we got from the remote servers.
    """
    @enforce_keys [:body, :headers, :status]
    defstruct [:body, :headers, :status]
  end

  defmodule Telemetry do
    # NOTE: to be DRYed with what is in the "transport" app later (`telemetry.ex`), if we stop using an umbrella app.
    # Currently we would have a circular dependency, or would have to move all this to `shared`.

    @proxy_requests [:internal, :external]

    @moduledoc """
    A quick place to centralize definition of tracing events and targets
    """

    def target_for_identifier(item_identifier) do
      "proxy:#{item_identifier}"
    end

    # This call will result in synchronous invoke of all registered handlers for the specified events.
    # (for instance, check out `Transport.Telemetry#handle_event`, available at time of writing)
    def trace_request(item_identifier, request_type) when request_type in @proxy_requests do
      :telemetry.execute([:proxy, :request, request_type], %{}, %{
        target: target_for_identifier(item_identifier)
      })
    end
  end

  def index(conn, _params) do
    text(conn, "Unlock Proxy")
  end

  # for now we use a whitelist which we'll gradually expand.
  # make sure to avoid including "hop-by-hop" headers here.
  @forwarded_headers_whitelist [
    "content-type",
    "content-length",
    "date",
    "last-modified",
    "etag"
  ]

  def fetch(conn, %{"id" => id}) do
    config = Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()

    resource = Map.get(config, id)

    if resource do
      conn
      |> process_resource(resource)
    else
      conn
      |> send_resp(404, "Not Found")
    end
  rescue
    exception ->
      # NOTE: handling this here for now because the main endpoint
      # will otherwise send a full HTML error page. We will have to
      # hook an unlock-specific handling for this instead.
      Logger.error("An exception occurred (#{exception |> inspect}")

      cond do
        # give a bit more context
        Mix.env() == :dev ->
          Logger.error(Exception.format_stacktrace())

        # avoid swallowed Mox expectations & ExUnit assertions
        Mix.env() == :test ->
          reraise exception, __STACKTRACE__
      end

      conn
      |> send_resp(500, "Internal Error")
  end

  # We put a hard limit on what can be cached, and otherwise will just
  # send back without caching. This means the remote server is less protected
  # temporarily, but also that we do not blow up our whole architecture due to
  # RAM consumption
  @max_allowed_cached_byte_size 20 * 1024 * 1024

  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.GTFS.RT{} = item) do
    Telemetry.trace_request(item.identifier, :external)
    response = fetch_remote(item)

    response.headers
    |> prepare_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # For now, we enforce the download. This will result in incorrect filenames
    # if the content-type is incorrect, but is better than nothing.
    |> put_resp_header("content-disposition", "attachment")
    |> send_resp(response.status, response.body)
  end

  defp process_resource(conn, %Unlock.Config.Item.GTFS.RT{}), do: send_not_allowed(conn)

  # NOTE: this code is designed for private use for now. I have tracked
  # what is required or useful for public opening later here:
  # https://github.com/etalab/transport-site/issues/2476
  defp process_resource(%{method: "POST"} = conn, %Unlock.Config.Item.SIRI{} = item) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

    parsed = Unlock.SIRI.parse_incoming(body)

    {modified_xml, external_requestor_refs} =
      Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref(parsed, item.requestor_ref)

    # NOTE: here we assert both that the requestor ref is what is expected, but also that it
    # is met once only. I am not deduping them at the moment on purpose, maybe we'll do that
    # later based on experience.
    if external_requestor_refs == [Application.fetch_env!(:unlock, :siri_public_requestor_ref)] do
      handle_authorized_siri_call(conn, item, modified_xml)
    else
      send_resp(conn, 403, "Forbidden")
    end
  end

  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.SIRI{}),
    do: send_not_allowed(conn)

  defp send_not_allowed(conn) do
    conn
    |> send_resp(405, "Method Not Allowed")
  end

  @spec handle_authorized_siri_call(Plug.Conn.t(), Unlock.Config.Item.SIRI.t(), Saxy.XML.element()) :: Plug.Conn.t()
  defp handle_authorized_siri_call(conn, %Unlock.Config.Item.SIRI{} = item, xml) do
    body = Saxy.encode_to_iodata!(xml)

    response = Unlock.HTTP.Client.impl().post!(item.target_url, item.request_headers, body)

    headers = response.headers |> lowercase_headers()

    # NOTE: for now, we unzip systematically. This will make it easier
    # to analyse payloads & later remove sensitive data, even if we
    # re-zip afterwards.
    # The Mint documentation contains useful bits to deal with more scenarios here
    # https://github.com/elixir-mint/mint/blob/main/pages/Decompression.md#decompressing-the-response-body
    gzipped = get_header(headers, "content-encoding") == ["gzip"]

    body = response.body

    body =
      if gzipped do
        :zlib.gunzip(body)
      else
        body
      end

    headers
    |> filter_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # No content-disposition as attachment for now
    |> send_resp(response.status, body)
  end

  defp fetch_remote(item) do
    comp_fn = fn _key ->
      Logger.info("Processing proxy request for identifier #{item.identifier}")

      try do
        Telemetry.trace_request(item.identifier, :internal)
        response = Unlock.HTTP.Client.impl().get!(item.target_url, item.request_headers)
        size = byte_size(response.body)

        if size > @max_allowed_cached_byte_size do
          Logger.warn("Payload is too large (#{size} bytes > #{@max_allowed_cached_byte_size}). Skipping cache.")
          {:ignore, response}
        else
          {:commit, response}
        end
      rescue
        e ->
          # NOTE: if an error occurs around the HTTP query, then
          # we want to track it down and return Bad Gateway
          Logger.error(Exception.format(:error, e, __STACKTRACE__))
          {:ignore, bad_gateway_response()}
      end
    end

    cache_name = Unlock.Shared.cache_name()
    cache_key = Unlock.Shared.cache_key(item.identifier)
    # NOTE: concurrent calls to `fetch` with the same key will result (here)
    # in only one fetching call, which is a nice guarantee (avoid overloading of target)
    {operation, result} = Cachex.fetch(cache_name, cache_key, comp_fn)

    case operation do
      :ok ->
        Logger.info("Proxy response for #{item.identifier} served from cache")
        result

      :commit ->
        # NOTE: in case of concurrent calls, the expire will be called 1 time per call. I am
        # doing research to verify if this could be changed (e.g. call `expire` inside the `comp_fn`),
        # but at this point it doesn't cause troubles.
        {:ok, true} = Cachex.expire(cache_name, cache_key, :timer.seconds(item.ttl))
        Logger.info("Setting cache TTL for key #{cache_key} (expire in #{item.ttl} seconds)")
        result

      :ignore ->
        Logger.info("Cache has been skipped for proxy response")
        result

      :error ->
        # NOTE: we'll want to have some monitoring here, but not using Sentry
        # because in case of troubles, we will blow up our quota.
        Logger.error("Error while fetching key #{cache_key}")
        bad_gateway_response()
    end
  end

  defp bad_gateway_response do
    %Unlock.HTTP.Response{status: 502, body: "Bad Gateway", headers: [{"content-type", "text/plain"}]}
  end

  # Inspiration https://github.com/elixir-plug/plug/blob/v1.13.6/lib/plug/conn.ex#L615
  defp get_header(headers, key) do
    for {^key, value} <- headers, do: value
  end

  defp lowercase_headers(headers) do
    headers
    |> Enum.map(fn {h, v} -> {String.downcase(h), v} end)
  end

  # Inspiration (MIT) here https://github.com/tallarium/reverse_proxy_plug
  defp filter_response_headers(headers) do
    headers
    |> Enum.filter(fn {h, _v} -> Enum.member?(@forwarded_headers_whitelist, h) end)
  end

  defp prepare_response_headers(headers) do
    headers
    |> lowercase_headers()
    |> filter_response_headers()
  end
end
