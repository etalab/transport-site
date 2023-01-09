defmodule Transport.Jobs.GTFSImportStopsJob do
  use Oban.Worker, max_attempts: 1
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    active_datasets_resource_history_items =
      DB.Dataset.base_query()
      |> DB.Resource.join_dataset_with_resource()
      |> DB.ResourceHistory.join_resource_with_latest_resource_history()
      |> where([resource: r], r.format == "GTFS")
      |> select([resource_history: rh], rh)
      |> DB.Repo.all()

    result =
      active_datasets_resource_history_items
      |> Enum.map(fn rh ->
        # TODO: wrap errors
        # TODO: create a global summary
        data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(rh.id)
        {:ok, %{resource_history_id: rh.id, data_import_id: data_import_id}}
      end)

    # TODO: delete all DataImport not referenced by active datasets items
    {:ok, result}
  end
end
