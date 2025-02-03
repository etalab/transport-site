defmodule Transport.PreemptiveAPICache do
  @moduledoc """
  A module that populates the Cachex cache for the /api/datasets endpoint ("api-datasets-index")
  """

  use GenServer
  require Logger

  @first_run 0
  @job_delay :timer.seconds(300)
  # slightly more than twice `@job_delay` to reduce the risk of parallel computation
  @cache_ttl :timer.seconds(700)

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
