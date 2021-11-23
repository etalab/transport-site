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
      # W
      Logger.error("An exception occurred (#{exception |> inspect}")
      conn
      |> send_resp(500, "Internal Error")
  end

  # We put a hard limit on what can be cached, and otherwise will just
  # send back without caching. This means the remote server is less protected
  # temporarily, but also that we do not blow up our whole architecture due to
  # RAM consumption
  @max_allowed_cached_byte_size 20 * 1024 * 1024

  defp trace_request(item_identifier, request_type) do
    :telemetry.execute([:proxy, :request, request_type], %{}, %{identifier: item_identifier})
  end

  defp process_resource(conn, item) do
    trace_request(item.identifier, :external)
    response = fetch_remote(item)

    response.headers
    |> prepare_response_headers()
    |> Enum.reduce(conn, fn {h, v}, c -> put_resp_header(c, h, v) end)
    # For now, we enforce the download. This will result in incorrect filenames
    # if the content-type is incorrect, but is better than nothing.
    |> put_resp_header("content-disposition", "attachment")
    |> send_resp(response.status, response.body)
  end

  defp fetch_remote(item) do
    comp_fn = fn _key ->
      Logger.info("Processing proxy request for identifier #{item.identifier}")
      try do
        trace_request(item.identifier, :internal)
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
          {:error, {:computation_error, e, __STACKTRACE__}}
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
        Cachex.expire(cache_name, cache_key, :timer.seconds(item.ttl))
        Logger.info("Setting cache TTL for key #{cache_key} (expire in #{item.ttl} seconds)")
        result
      :ignore ->
        Logger.info("Cache has been skipped for proxy response")
        result
      :error ->
        # NOTE: we'll want to have some monitoring here, but not using Sentry
        # because in case of troubles, we will blow up our quota.
        %Unlock.HTTP.Response{status: 502, body: "Bad Gateway", headers: [{"content-type", "text/plain"}]}
    end
  end

  # Inspiration (MIT) here https://github.com/tallarium/reverse_proxy_plug
  defp prepare_response_headers(headers) do
    headers
    |> Enum.map(fn {h, v} -> {String.downcase(h), v} end)
    |> Enum.filter(fn {h, _v} -> Enum.member?(@forwarded_headers_whitelist, h) end)
  end
end
