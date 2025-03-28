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
  import Unlock.GunzipTools

  def index(conn, _params) do
    text(conn, "Unlock Proxy")
  end

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

  # In particular, it can be desirable to let the config override "content-disposition"
  # to specify a filename (in the case of IRVE data for instance, which is CSV and most
  # users expect it to download as a file, contrary to other formats)
  defp override_resp_headers_if_configured(conn, %Unlock.Config.Item.Generic.HTTP{} = item) do
    Enum.reduce(item.response_headers, conn, fn {header, value}, conn ->
      conn
      |> put_resp_header(header |> String.downcase(), value)
    end)
  end

  defp to_nil_or_integer(nil), do: nil
  defp to_nil_or_integer(data), do: String.to_integer(data)
  defp to_boolean(nil), do: false
  defp to_boolean("0"), do: false
  defp to_boolean("1"), do: true

  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.Aggregate{} = item) do
    Unlock.Telemetry.trace_request(item.identifier, :external)
    # NOTE: required for tests to work, and doesn't hurt in production (idempotent afaik)
    conn = conn |> Plug.Conn.fetch_query_params()

    options = [
      limit_per_source: conn.query_params["limit_per_source"] |> to_nil_or_integer(),
      include_origin: conn.query_params["include_origin"] |> to_boolean()
    ]

    body_response = Unlock.AggregateProcessor.process_resource(item, options)
    send_resp(conn, 200, body_response)
  end

  defp process_resource(%{method: "GET"} = conn, %Unlock.Config.Item.Generic.HTTP{} = item) do
    Unlock.Telemetry.trace_request(item.identifier, :external)
    response = fetch_remote(item)

    response.headers
    |> prepare_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # For now, we enforce the download. This will result in incorrect filenames
    # if the content-type is incorrect, but is better than nothing.
    |> put_resp_header("content-disposition", "attachment")
    |> override_resp_headers_if_configured(item)
    |> send_resp(response.status, response.body)
  end

  defp process_resource(conn, %Unlock.Config.Item.Generic.HTTP{}), do: send_not_allowed(conn)

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
    body = Saxy.encode_to_iodata!(xml, version: "1.0")

    response = Unlock.HTTP.Client.impl().post!(item.target_url, item.request_headers, body)

    headers = response.headers |> lowercase_headers()

    # NOTE: for now, we unzip systematically. This will make it easier
    # to analyse payloads & later remove sensitive data, even if we
    # re-zip afterwards.
    body = maybe_gunzip(response.body, headers)

    headers
    |> filter_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # No content-disposition as attachment for now
    |> send_resp(response.status, body)
  end

  defp fetch_remote(%Unlock.Config.Item.Generic.HTTP{} = item) do
    comp_fn = fn _key ->
      Logger.debug("Processing proxy request for identifier #{item.identifier}")

      try do
        Unlock.Telemetry.trace_request(item.identifier, :internal)
        Unlock.CachedFetch.fetch_data(item)
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
    outcome = Cachex.fetch(cache_name, cache_key, comp_fn)

    case outcome do
      {:ok, result} ->
        Logger.debug("Proxy response for #{item.identifier} served from cache")
        result

      {:commit, result, _options} ->
        result

      {:ignore, result} ->
        Logger.debug("Cache has been skipped for proxy response")
        result

      {:error, _error} ->
        # NOTE: we'll want to have some monitoring here, but not using Sentry
        # because in case of troubles, we will blow up our quota.
        Logger.error("Error while fetching key #{cache_key}")
        bad_gateway_response()
    end
  end

  defp bad_gateway_response do
    %Unlock.HTTP.Response{status: 502, body: "Bad Gateway", headers: [{"content-type", "text/plain"}]}
  end

  # Inspiration (MIT) here https://github.com/tallarium/reverse_proxy_plug
  defp filter_response_headers(headers) do
    Enum.filter(headers, fn {h, _v} -> Enum.member?(Shared.Proxy.forwarded_headers_allowlist(), h) end)
  end

  defp prepare_response_headers(headers) do
    headers
    |> lowercase_headers()
    |> filter_response_headers()
  end
end
