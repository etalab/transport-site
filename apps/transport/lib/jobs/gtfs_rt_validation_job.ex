defmodule Transport.Jobs.GTFSRTValidationDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `GTFSRTValidationJob`.
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    relevant_datasets()
    |> Enum.map(&(%{dataset_id: &1.id} |> Transport.Jobs.GTFSRTValidationJob.new()))
    |> Oban.insert_all()

    :ok
  end

  def relevant_datasets do
    today = Date.utc_today()

    sub =
      Resource
      |> where([r], r.format == "GTFS" and r.is_available)
      |> where([r], r.start_date <= ^today and r.end_date >= ^today)
      |> select([r], r.dataset_id)
      |> group_by([r], r.dataset_id)
      |> having([r], count(r.id) == 1)

    Dataset
    |> join(:inner, [d], r in Resource, on: r.dataset_id == d.id)
    |> where([_d, r], r.format == "gtfs-rt" and r.is_available)
    |> where([d, _r], d.is_active and d.id in subquery(sub))
    |> distinct(true)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.GTFSRTValidationJob do
  @moduledoc """
  Job validating gtfs-rt resources and saving validation
  results.
  """
  use Oban.Worker, max_attempts: 5, tags: ["validation"]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
  end
end
