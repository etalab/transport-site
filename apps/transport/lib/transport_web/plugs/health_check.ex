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

    cond do
      conn.request_path == path ->
        conn = fetch_query_params(conn)
        {global_success, messages} = run_checks(conn.query_params)

        status = if global_success, do: 200, else: 500

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(status, messages |> Enum.join("\n"))
        |> halt()

      conn.request_path == path <> "/metrics" ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, get_metrics() |> Enum.join("\n"))
        |> halt()

      true ->
        conn
    end
  end

  defp checks do
    [
      %{name: "db", check: &database_up?/0},
      %{name: "http", check: fn -> true end}
    ]
  end

  # experimental at the moment, in order to help
  # get more insights at what's happening inside
  # the worker container.
  # see https://www.erlang.org/doc/man/memsup.html#get_system_memory_data-0
  defp get_metrics do
    :memsup.get_system_memory_data()
    |> Enum.map(fn {k, v} -> "#{k}: #{v} (#{Sizeable.filesize(v)})" end)
  end

  @spec run_checks(map()) :: {boolean(), list()}
  defp run_checks(params) do
    checks()
    |> Enum.reject(fn %{name: name} -> params[name] == "0" end)
    |> Enum.map(fn %{name: name, check: cb} -> {name, cb.()} end)
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
