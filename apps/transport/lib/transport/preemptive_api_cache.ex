defmodule Transport.PreemptiveAPICache do
  @moduledoc """
  A module that populates the Cachex cache for the /api/datasets endpoint ("api-datasets-index")
  """

  use Transport.PreemptiveBaseCache,
    first_run: :timer.seconds(30),
    job_delay: :timer.seconds(300),
    # more than twice job_delay to reduce the risk of parallel computation
    cache_ttl: :timer.seconds(700)

  require Logger

  def populate_cache do
    Logger.info("[preemptive-api-cache] Populating cache for /api/datasets…")

    Transport.Cache.put(
      "api-datasets-index",
      # NOTE: the structure saved in Cachex is currently an Elixir structure,
      # not the final JSON. We may have to persist JSON directly instead to
      # reduce memory use in the future.
      TransportWeb.API.DatasetController.prepare_datasets_index_data(),
      @cache_ttl
    )

    Logger.info("[preemptive-api-cache] Finished populating cache for /api/datasets.")
  end
end
