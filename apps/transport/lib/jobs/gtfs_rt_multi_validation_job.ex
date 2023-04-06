defmodule Transport.Jobs.GTFSRTMultiValidationDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTMultiValidationJob`.
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]
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

  @doc """
  Identifies datasets with at least 1 available GTFS-RT resource.
  The GTFS-RT validator will be responsible to determine if the dataset can be validated,
  based on the number of up-to-date GTFS and related resources.
  """
  def relevant_datasets do
    DB.Dataset.base_query()
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], r.format == "gtfs-rt" and r.is_available)
    |> distinct(true)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTMultiValidationJob do
  @moduledoc """
  Job validating gtfs-rt resources and saving validation
  results.
  """
  use Oban.Worker, max_attempts: 5, queue: :resource_validation, tags: ["validation"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    Transport.Validators.GTFSRT.validate_and_save(DB.Repo.get!(DB.Dataset, dataset_id))
  end

  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    Transport.Validators.GTFSRT.validate_and_save(DB.Repo.get!(DB.Resource, resource_id))
  end
end
