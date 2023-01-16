defmodule Transport.Jobs.GTFSImportStopsJob do
  @moduledoc """
  A job to import all stops from all active GTFS, and report on that.
  """
  use Oban.Worker, max_attempts: 1
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    # NOTE: at some point deleting DataImport not referenced by active datasets item will be a good idea,
    # to avoid leaving obsolete stuff in the database.
    result = {:ok, refresh_all()}
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id})
    result
  end

  def refresh_all do
    result =
      active_datasets_resource_history_items()
      |> refresh()

    batch =
      %DB.DataImportBatch{summary: %{result: result}}
      |> DB.Repo.insert!()

    %{result: result, data_import_batch_id: batch.id}
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
      Logger.info("Processing rh_id=#{rh.id}")

      try do
        data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(rh.id)
        %{resource_history_id: rh.id, status: :ok, data_import_id: data_import_id}
      rescue
        error ->
          %{
            resource_history_id: rh.id,
            resource_id: rh.resource_id,
            status: :error,
            error: error |> inspect(),
            error_message: safe_call(fn -> Map.get(error, :message) end, "unknown"),
            error_struct: safe_call(fn -> error.__struct__ |> inspect end, "unknown")
          }
      end
    end)
  end

  def safe_call(cb, default) do
    cb.()
  rescue
    _ -> default
  end
end
