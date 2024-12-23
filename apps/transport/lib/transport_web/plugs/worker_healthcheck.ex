defmodule TransportWeb.Plugs.WorkerHealthcheck do
  @moduledoc """
  A plug for the worker.
  It can be conditionally enabled by passing an `:if` condition that will be evaluated.

  It displays:
  - when the app was started
  - the last attempt for Oban jobs
  - if the system is healthy

  The system is considered:
  - healthy if the app was started recently or if Oban attempted jobs recently.
  - not healthy: we don't respond to incoming HTTP requests by halting
  the connection and expect our hosting provider to reboot the app.
  """
  import Plug.Conn

  @app_start_waiting_delay {20, :minute}
  @oban_max_delay_since_last_attempt {60, :minute}

  def init(options), do: options

  def call(conn, opts) do
    {mod, fun} = opts[:if]

    if apply(mod, fun, []) do
      store_last_attempted_at_delay_metric()

      if healthy_state?() do
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, """
        UP (WORKER-ONLY)
        App start time: #{app_start_datetime()}
        App started recently?: #{app_started_recently?()}
        Oban last attempt: #{oban_last_attempted_at()}
        Oban attempted jobs recently?: #{oban_attempted_jobs_recently?()}
        Healthy state?: #{healthy_state?()}
        """)
        |> halt()
      else
        conn |> halt()
      end
    else
      conn
    end
  end

  def store_last_attempted_at_delay_metric do
    value = DateTime.diff(oban_last_attempted_at(), DateTime.utc_now(), :second)
    Appsignal.add_distribution_value("oban.last_attempted_at_delay", value)
  end

  def healthy_state? do
    app_started_recently?() or oban_attempted_jobs_recently?()
  end

  def app_started_recently? do
    {delay, unit} = @app_start_waiting_delay
    DateTime.diff(DateTime.utc_now(), app_start_datetime(), unit) < delay
  end

  def app_start_datetime do
    Transport.Cache.fetch(app_start_datetime_cache_key_name(), fn -> DateTime.utc_now() end, expire: nil)
  end

  def app_start_datetime_cache_key_name, do: "#{__MODULE__}::app_start_datetime"

  def oban_attempted_jobs_recently? do
    {delay, unit} = @oban_max_delay_since_last_attempt
    DateTime.after?(oban_last_attempted_at(), DateTime.add(DateTime.utc_now(), -delay, unit))
  end

  def oban_last_attempted_at do
    %Postgrex.Result{rows: [[delay]]} =
      DB.Repo.query!("""
      SELECT MAX(attempted_at)
      FROM oban_jobs
      WHERE state = 'completed'
      """)

    case delay do
      nil -> DateTime.new!(~D[1970-01-01], ~T[00:00:00.000], "Etc/UTC")
      %NaiveDateTime{} = nt -> DateTime.from_naive!(nt, "Etc/UTC")
    end
  end
end
