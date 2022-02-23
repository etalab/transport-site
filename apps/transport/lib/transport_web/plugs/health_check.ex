defmodule TransportWeb.Plugs.HealthCheck do
  @moduledoc """
    A lightweight monitoring check, running as a plug to make sure we can have it for both the site
    and the worker instances.
    The goal is to quickly verify if the database is up, leave some room for extra future checks,
    and return 200/500 depending on the situation.
  """
  import Plug.Conn

  def init(options), do: options

  def call(conn, opts) do
    path = opts[:at]

    if conn.request_path == path do
      success = database_up?()
      message = "DATABASE: " <> if success, do: "OK", else: "KO"
      status = if success, do: 200, else: 500

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(status, message)
      |> halt()
    else
      conn
    end
  end

  defp database_up? do
    query = Ecto.Adapters.SQL.query!(DB.Repo, "select 0", [])
    query.rows == [[0]]
  rescue
    _ in DBConnection.ConnectionError -> false
  end
end
