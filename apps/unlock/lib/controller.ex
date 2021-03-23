defmodule Unlock.Controller do
  @moduledoc """
  The main controller for proxying
  """

  use Phoenix.Controller
  require Logger

  def index(conn, _params) do
    text(conn, "Unlock Proxy")
  end

  def fetch(conn, %{"id" => id}) do
    config = Application.get_env(:unlock, :resources)
    config = config.()
    # TODO: handle 404 properly
    resource = config |> Map.fetch!(id)
    # TODO: handle 500 properly
    %{"url" => url, "ttl" => _ttl} = resource
    Logger.info "Proxy match found for id #{id}"

    # NOTE: if needed, pool size can be customized (this could be useful if
    # we see a large number of slow target responses)
    # https://hexdocs.pm/httpoison/readme.html#connection-pools
    # NOTE: in case of timeouts here, check out `recv_timeout` option
    response = HTTPoison.get!(url, [], recv_timeout: 10_000)

    # TODO: handle some response headers at least
    # TODO: add a bit of in-memory caching
    # TODO: handle errors by sending 502 bad gateway
    # TODO: integrate Sentry for error reporting
    conn
    |> send_resp(response.status_code, response.body)
  end
end
