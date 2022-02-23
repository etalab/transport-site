defmodule TransportWeb.HealthCheckController do
  use TransportWeb, :controller

  def index(conn, params) do
    result = run_check()

    conn
    |> put_status(result.status)
    |> json(result.json)
  end

  defp run_check() do
    up = database_up?()

    %{
      status: if(up, do: 200, else: 500),
      json: %{
        database: if(up, do: "OK", else: "KO")
      }
    }
  end

  defp database_up? do
    try do
      query = Ecto.Adapters.SQL.query!(DB.Repo, "select 0", [])
      query.rows == [[0]]
    rescue
      _ in DBConnection.ConnectionError -> false
    end
  end
end
