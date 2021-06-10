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

    # TODO: handle 404 properly
    resource = config |> Map.fetch!(id)
    # TODO: handle 500 properly
    Logger.info "Proxy match found for id #{id}"

    response = Unlock.HTTP.Client.impl().get!(resource.target_url, [])

    # TODO: add a bit of in-memory caching, but forbid too large payloads
    # TODO: handle errors by sending 502 bad gateway
    # TODO: integrate Sentry for error reporting

    prepare_response_headers(response.headers)
    |> Enum.reduce(conn, fn {h,v}, c -> put_resp_header(c,h,v) end)
    |> send_resp(response.status, response.body)
  end

  # Inspiration (MIT) here https://github.com/tallarium/reverse_proxy_plug
  defp prepare_response_headers(headers) do
    headers
    |> Enum.map(fn {h,v} -> {String.downcase(h) ,v} end)
    |> Enum.filter(fn {h,_v} -> Enum.member?(@forwarded_headers_whitelist, h) end)
  end
end
