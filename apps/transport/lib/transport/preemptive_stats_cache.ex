defmodule Transport.PreemptiveStatsCache do
  @moduledoc """
  A module that populates the Cachex cache for the /stats and /api/stats/* endpoints
  """

  use Transport.PreemptiveBaseCache,
    # Let’s give some time for the system to boot up before we start and the API cache to be populated
    first_run: :timer.minutes(1),
    job_delay: :timer.hours(3),
    # more than twice job_delay to reduce the risk of parallel computation
    cache_ttl: :timer.hours(7)

  require Logger

  def populate_cache do
    Logger.info("[preemptive-stats-cache] Populating cache for stats…")
    Transport.Cache.put("stats-page-index", Transport.StatsHandler.compute_stats(), @cache_ttl)
    Transport.Cache.put("api-stats-aoms", TransportWeb.API.StatsController.rendered_geojson(:aoms), @cache_ttl)
    Transport.Cache.put("api-stats-regions", TransportWeb.API.StatsController.rendered_geojson(:regions), @cache_ttl)
    Transport.Cache.put("api-stats-quality", TransportWeb.API.StatsController.rendered_geojson(:quality), @cache_ttl)
    Logger.info("[preemptive-stats-cache] Finished populating cache for stats.")
  end
end
