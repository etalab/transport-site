defmodule TransportWeb.Plugs.WorkerHealthcheck do
  @moduledoc """
  A plug for the worker.
  It can be conditionally enabled by passing an `:if` condition that will be evaluated.

  It displays:
  - when the app was started
  - the last attempt for Oban jobs
  - if the system is healthy

  The system is considered healthy if the app was started recently or
  if Oban attempted jobs recently.
  """
  import Plug.Conn
  require Logger

  @app_start_waiting_delay {20, :minute}
  @oban_max_delay_since_last_attempt {60, :minute}

  def init(options), do: options

  def call(conn, opts) do
    {mod, fun} = opts[:if]

    if apply(mod, fun, []) do
      store_last_attempted_at_delay_metric()
      status_code = if healthy_state?(), do: 200, else: 503

      conn =
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(status_code, """
        UP (WORKER-ONLY)
        App start time: #{app_start_datetime()}
        App started recently?: #{app_started_recently?()}
        Oban last attempt: #{oban_last_attempted_at()}
        Oban attempted jobs recently?: #{oban_attempted_jobs_recently?()}
        Healthy state?: #{healthy_state?()}
        """)
        |> halt()

      # NOTE: Clever Cloud monitoring will better pick stuff back up
      # if the app is completely down.
      if !healthy_state?() do
        Logger.info("Hot-fix: shutting down!!!")
        stop_the_beam!()
      end

      conn
    else
      conn
    end
  end

  @doc """
  A fix for https://github.com/etalab/transport-site/issues/4377.

  If the worker sees that no jobs have been attempted by Oban for some time,
  this plug's logic stops the whole program (BEAM/VM) completely. Because the
  Clever Cloud monitoring checks that they can open a socket to the 8080 port,
  this makes the test fails, hence resulting in an automatic restart.

  This is a cheap but so far effective way to ensure the worker gets restarted
  when it malfunctions.
  """
  def stop_the_beam! do
    # "Asynchronously and carefully stops the Erlang runtime system."
    if Mix.env() == :test do
      # We do not want to stop the system during tests, because it
      # gives the impression the test suite completed successfully, but
      # it would actually just bypass all the tests after the one running this!
      raise "would halt the BEAM"
    else
      # Also make sure to return with a non-zero exit code, to more clearly
      # indicate that this is not the normal output
      System.stop(1)
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
