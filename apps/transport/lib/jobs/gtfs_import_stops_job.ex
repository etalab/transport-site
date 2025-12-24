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

    # for now, just chain view creation/refresh directly
    Logger.info("Creating or refreshing materialized views...")
    Transport.GTFSData.create_or_refresh_all_materialized_views()
    Logger.info("Done with refresh...")

    result
  end

  def refresh_all do
    result =
      active_up_to_date_datasets_resource_history_items()
      |> refresh()

    batch =
      %DB.DataImportBatch{summary: %{result: result}}
      |> DB.Repo.insert!()

    clean_up_stale_imports()

    %{result: result, data_import_batch_id: batch.id}
  end

  # Doing some cleanup operations:
  # - remove data imports for deleted resources
  # - remove data imports for inactive datasets
  #
  # This, combined with the existing code in `gtfs_import_stops.ex` to remove
  # previous data import for same resource history and previous data import
  # for other resource history for the same resource, should cover most cases.
  #
  # To ensure there is only one data import per resource, and no NULL resources,
  # one can use the following query & verify it returns nothing:
  #
  # ```sql
  # select r.id, count(*) from data_import di
  # left join resource_history rh on rh.id = di.resource_history_id
  # left join resource r on r.id = rh.resource_id
  # group by r.id
  # having count(*) > 1
  # ```
  #
  # If we need more features in the future, it could be a good idea to instead
  # import "all current stuff" in temporary tables (staging area), then
  # merge/insert/update/delete in the real tables, to avoid fiddling around too much.
  #
  def clean_up_stale_imports do
    Logger.info("Removing DataImports for deleted resources")
    query = from(di in DB.DataImport)

    data_import_ids =
      query
      |> join(:left, [di], rh in DB.ResourceHistory, on: di.resource_history_id == rh.id)
      |> join(:left, [di, rh], r in DB.Resource, on: rh.resource_id == r.id)
      |> where([di, rh, r], is_nil(r.id))
      |> select([di, rh, r], di.id)
      |> DB.Repo.all()

    # process in smaller batches to avoid putting to much stress on the database
    # and also increase the timeout
    data_import_ids
    |> Enum.chunk_every(5)
    |> Enum.each(fn data_import_ids ->
      query = from(di in DB.DataImport, where: di.id in ^data_import_ids)
      query |> DB.Repo.delete_all(timeout: 60_000)
    end)

    Logger.info("Removing DataImports for inactive datasets")

    query = from(di in DB.DataImport)

    data_import_ids =
      query
      |> join(:left, [di], rh in DB.ResourceHistory, on: di.resource_history_id == rh.id)
      |> join(:left, [di, rh], r in DB.Resource, on: rh.resource_id == r.id)
      |> join(:left, [di, rh, r], d in DB.Dataset, on: r.dataset_id == d.id)
      |> where([di, rh, r, d], d.is_active == false)
      |> select([di, rh, r], di.id)
      |> DB.Repo.all()

    data_import_ids
    |> Enum.chunk_every(5)
    |> Enum.each(fn data_import_ids ->
      query = from(di in DB.DataImport, where: di.id in ^data_import_ids)
      query |> DB.Repo.delete_all(timeout: 60_000)
    end)
  end

  def active_up_to_date_datasets_resource_history_items do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(
      Enum.map(Transport.ValidatorsSelection.validators_for_feature(:gtfs_import_stops_job), & &1.validator_name())
    )
    |> DB.ResourceMetadata.where_gtfs_up_to_date()
    |> where([resource: r], r.format == "GTFS")
    |> select([resource_history: rh], rh)
    |> DB.Repo.all()
  end

  def refresh(resource_history_items) do
    resource_history_items
    |> Enum.map(fn rh ->
      Logger.info("Processing rh_id=#{rh.id}")

      common_data = %{
        resource_history_id: rh.id,
        resource_id: rh.resource_id
      }

      try do
        data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(rh.id)

        %{
          status: :ok,
          data_import_id: data_import_id
        }
        |> Map.merge(common_data)
      rescue
        error ->
          %{
            status: :error,
            error: error |> inspect(),
            error_message: safe_call(fn -> Map.get(error, :message) end, "unknown"),
            error_struct: safe_call(fn -> error.__struct__ |> inspect end, "unknown")
          }
          |> Map.merge(common_data)
      end
    end)
  end

  def safe_call(cb, default) do
    cb.()
  rescue
    _ -> default
  end
end
