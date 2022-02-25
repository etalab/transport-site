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
      conn = fetch_query_params(conn)
      {global_success, messages} = run_checks(conn.query_params)

      status = if global_success, do: 200, else: 500

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(status, messages |> Enum.join("\n"))
      |> halt()
    else
      conn
    end
  end

  defp checks do
    %{
      "http" => fn -> true end,
      "db" => &database_up?/0
    }
  end

  @spec run_checks(map()) :: {boolean(), list()}
  defp run_checks(params) do
    checks
    |> Enum.reject(fn {name, _} -> params[name] == "0" end)
    |> Enum.map(fn {name, cb} -> {name, cb.()} end)
    |> Enum.reduce({true, []}, fn {check_name, check_success}, {global_success, messages} ->
      {
        global_success && check_success,
        messages ++ ["#{check_name}: " <> if(check_success, do: "OK", else: "KO")]
      }
    end)
  end

  defp database_up? do
    query = Ecto.Adapters.SQL.query!(DB.Repo, "select 0", [])
    query.rows == [[0]]
  rescue
    _ in DBConnection.ConnectionError -> false
  end
end
