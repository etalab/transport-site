defmodule Transport.Jobs.GTFSRTMultiValidationDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTMultiValidationJob`.
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  import Ecto.Query
  alias DB.{Repo, Resource}
  alias Transport.Validators.GTFSTransport

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_datasets()
    |> Enum.map(&(%{dataset_id: &1.id} |> Transport.Jobs.GTFSRTMultiValidationJob.new()))
    |> Oban.insert_all()

    :ok
  end

  def relevant_datasets do
    # relevant datasets are active datasets having a gtfs-rt and a single GTFS resource,
    # that is both available and up to date

    resources =
      DB.Resource.base_query()
      |> DB.ResourceHistory.join_resource_with_latest_resource_history()
      |> DB.MultiValidation.join_resource_history_with_latest_validation(GTFSTransport.validator_name())
      |> DB.ResourceMetadata.join_validation_with_metadata()
      |> where([resource: r], r.format == "GTFS" and r.is_available)
      |> DB.ResourceMetadata.where_gtfs_up_to_date()
      |> select([resource: r], r.dataset_id)
      |> group_by([resource: r], r.dataset_id)
      |> having([resource: r], count(r.id) == 1)

    DB.Dataset.base_query()
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], r.format == "gtfs-rt" and r.is_available)
    |> where([d], d.id in subquery(resources))
    |> distinct(true)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTMultiValidationJob do
  @moduledoc """
  Job validating gtfs-rt resources and saving validation
  results.
  """
  use Oban.Worker, max_attempts: 5, tags: ["validation"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    Transport.Validators.GTFSRT.validate_and_save(DB.Repo.get!(DB.Dataset, dataset_id))
  end

  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    Transport.Validators.GTFSRT.validate_and_save(DB.Repo.get!(DB.Resource, resource_id))
  end
end
