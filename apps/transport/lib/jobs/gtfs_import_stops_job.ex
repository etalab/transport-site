defmodule Transport.Jobs.GTFSImportStopsJob do
  use Oban.Worker, max_attempts: 1
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # TODO: delete all DataImport not referenced by active datasets items
    {:ok, refresh_all()}
  end

  def refresh_all() do
    active_datasets_resource_history_items()
    |> refresh()
  end

  def active_datasets_resource_history_items do
    DB.Dataset.base_query()
    |> DB.Resource.join_dataset_with_resource()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> where([resource: r], r.format == "GTFS")
    |> select([resource_history: rh], rh)
    |> DB.Repo.all()
  end

  def refresh(resource_history_items) do
    resource_history_items
    |> Enum.map(fn rh ->
      # TODO: create a global summary
      Logger.info("Processing rh_id=#{rh.id}")

      try do
        data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(rh.id)
        {:ok, %{resource_history_id: rh.id, data_import_id: data_import_id}}
      rescue
        error ->
          {:error, %{resource_history_id: rh.id, error: error}}
      end
    end)
  end
end
