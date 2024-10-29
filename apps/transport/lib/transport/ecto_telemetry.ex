defmodule Transport.EctoTelemetry do
  require Logger

  @moduledoc """
  A module receiving Ecto events and forwarding them (currently) to AppSignal, so that we can
  chart the pool occupancy.

  References:
  * https://hexdocs.pm/ecto/Ecto.Repo.html#module-telemetry-events
  * https://github.com/appsignal/appsignal-elixir/issues/318#issuecomment-841156779 (inspiration)
  * https://elixirforum.com/t/how-to-deal-with-detached-telemetry-handlers-caused-by-errors/56069/2
  * https://github.com/appsignal/appsignal-elixir/issues/887 (which ensures calls are fast & mostly safe)

  A few notes extracted from the doc (with extra comments):
  * `:idle_time` - the time the connection spent waiting before being checked out for the query.
                 the higher the better ; if this gets low (close to 0), the pool is over-used (not good).
  * `:queue_time` - the time spent waiting to check out a database connection.
                  the lower the better. if this gets too high, the pool is over-used (not good).
  * `:query_time` - the time spent executing the query.

  We do not track the following metrics for now, because they are less useful for pool optimization:
  * `:decode_time` - the time spent decoding the data received from the database
  * `:total_time` - the sum of (queue_time, query_time, and decode_time)️

  It must be noted that handlers are running inline, and that they can be "detached" in case of errors.

  In the case of this implementation, the risk is just losing metrics, which is acceptable, plus the way
  AppSignal works (see above discussions) makes this risk not very likely to occur.
  """

  def handle_event([:db, :repo, :query], measurements, _metadata, _config) do
    #
    # NOTE: at time of writing, at AppSignal, "Custom metrics do not count towards your plan.
    # Only requests and logging. Custom metrics are included.".
    #
    # If we need to reduce the volume of metrics (for billing or ops reasons), it appears that
    # Oban emits roughly 5 calls every 500ms in development at least (setting `WORKER=0` removes those events).
    # If this is a problem, we can probably filter a part of them via metadata[:options][:oban_conf] which
    # appears to be there, but for now I believe this gives useful information too.
    #

    case measurements do
      %{queue_time: queue_time} ->
        Appsignal.add_distribution_value("ecto.queue_time", System.convert_time_unit(queue_time, :native, :millisecond))

      _ ->
        nil
    end

    case measurements do
      %{idle_time: idle_time} ->
        Appsignal.add_distribution_value("ecto.idle_time", System.convert_time_unit(idle_time, :native, :millisecond))

      _ ->
        nil
    end

    case measurements do
      %{query_time: query_time} ->
        Appsignal.add_distribution_value("ecto.query_time", System.convert_time_unit(query_time, :native, :millisecond))

      _ ->
        nil
    end
  end

  def setup do
    Logger.info("Setting up telemetry for AppSignal + Ecto")

    :telemetry.attach(
      "transport-ecto",
      # NOTE: the first two params are I believe mapped to `DB.Repo`
      [:db, :repo, :query],
      &Transport.EctoTelemetry.handle_event/4,
      nil
    )
  end
end
