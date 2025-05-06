defmodule Transport.PreemptiveHomeStatsCache do
  @moduledoc """
  A module that populates the Cachex cache for the home page stats ("home-index-stats")
  """

  use Transport.PreemptiveBaseCache,
    first_run: 0,
    job_delay: :timer.hours(4),
    # more than twice job_delay to reduce the risk of parallel computation
    cache_ttl: :timer.hours(9)

  require Logger

  def populate_cache do
    Logger.info("[preemptive-home-cache] Populating cache for homepage stats…")

    Transport.Cache.put(
      "home-index-stats",
      TransportWeb.PageController.compute_home_index_stats(),
      @cache_ttl
    )

    Logger.info("[preemptive-home-cache] Finished populating cache for homepage stats.")
  end
end
