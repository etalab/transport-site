defmodule Transport.Jobs.GBFSMultiValidationDispatcherJob do
  @moduledoc """
  Job in charge of validating multiple GBFS resources.
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  alias Transport.Jobs.GBFSMultiValidationJob
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_resources()
    |> Enum.map(&(%{resource_id: &1} |> GBFSMultiValidationJob.new()))
    |> Oban.insert_all()

    :ok
  end

  def relevant_resources do
    DB.Resource.base_query()
    |> where([r], r.is_available and r.format == "gbfs")
    |> select([r], r.id)
    |> DB.Repo.all()
  end
end

defmodule Transport.Jobs.GBFSMultiValidationJob do
  @moduledoc """
  Job in charge of validating a GBFS resource.
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  alias Transport.Validators.GBFSValidator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    DB.Resource
    |> DB.Repo.get!(resource_id)
    |> GBFSValidator.validate_and_save()
  end
end
