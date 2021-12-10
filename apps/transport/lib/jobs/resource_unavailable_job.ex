defmodule Transport.Jobs.ResourcesUnavailableDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceUnavailableJob`
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(_job) do
    resource_ids = resources_to_check()

    Logger.debug("Dispatching #{Enum.count(resource_ids)} ResourceUnavailableJob jobs")

    resource_ids
    |> Enum.map(fn resource_id ->
      %{resource_id: resource_id} |> Transport.Jobs.ResourceUnavailableJob.new()
    end)
    |> Oban.insert_all()

    :ok
  end

  def resources_to_check do
    Resource
    |> join(:inner, [r], d in DB.Dataset, on: r.dataset_id == d.id and d.is_active)
    |> where([r], not r.is_community_resource)
    |> where([r], like(r.url, "http%"))
    |> select([r], r.id)
    |> Repo.all()
  end
end

defmodule Transport.Jobs.ResourceUnavailableJob do
  @moduledoc """
  Job checking if a resource is available over HTTP or not and
  storing unavailabilities in that case.
  """
  use Oban.Worker, max_attempts: 5
  require Logger
  import Ecto.Query
  alias DB.{Repo, Resource}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    Logger.info("Running ResourceUnavailableJob for #{resource_id}")
    _resource = Resource |> where([r], r.id == ^resource_id) |> Repo.one!()

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
