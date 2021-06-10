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
    config = Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()

    # TODO: handle 404 properly
    resource = config |> Map.fetch!(id)
    # TODO: handle 500 properly
    Logger.info "Proxy match found for id #{id}"

    response = Unlock.HTTP.Client.impl().get!(resource.target_url, [])

    # TODO: handle some response headers at least
    # TODO: add a bit of in-memory caching
    # TODO: handle errors by sending 502 bad gateway
    # TODO: integrate Sentry for error reporting
    conn
    |> send_resp(response.status, response.body)
  end
end
