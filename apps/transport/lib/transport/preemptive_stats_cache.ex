defmodule Transport.PreemptiveStatsCache do
  @moduledoc """
  A module that populates the Cachex cache for the /api/datasets endpoint ("api-datasets-index")
  """

  use GenServer
  require Logger

  # Let’s give some time for the system to boot up before we start
  @first_run :timer.minutes(1)
  # We want to refresh the cache every 3 hours
  @job_delay :timer.hours(3)
  # slightly more than twice `@job_delay` to reduce the risk of parallel computation
  @cache_ttl :timer.hours(7)

  def cache_ttl, do: @cache_ttl

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    # initial schedule is immediate, but via the same code path,
    # to ensure we jump on the data
    schedule_next_occurrence(@first_run)

    {:ok, state}
  end

  def schedule_next_occurrence(delay \\ @job_delay) do
    Process.send_after(self(), :tick, delay)
  end

  def handle_info(:tick, state) do
    schedule_next_occurrence()
    populate_cache()
    {:noreply, state}
  end

  def populate_cache do
    Logger.info("[preemptive-stats-cache] Populating cache for stats…")
    Transport.Cache.put("stats-page-index", Transport.StatsHandler.compute_stats(), @cache_ttl)
    Transport.Cache.put("api-stats-aoms", TransportWeb.API.StatsController.rendered_geojson(:aoms), @cache_ttl)
    Transport.Cache.put("api-stats-regions", TransportWeb.API.StatsController.rendered_geojson(:regions), @cache_ttl)
    Transport.Cache.put("api-stats-quality", TransportWeb.API.StatsController.rendered_geojson(:quality), @cache_ttl)
    Logger.info("[preemptive-stats-cache] Finished populating cache for stats.")
  end
end
