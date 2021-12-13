defmodule Transport.Jobs.ResourcesUnavailableDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `ResourceUnavailableJob`
  """
  use Oban.Worker, max_attempts: 3
  require Logger
  import Ecto.Query
  alias DB.{Dataset, Repo, Resource, ResourceUnavailability}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    resource_ids = resources_to_check(Map.get(args, "only_unavailable", false))

    Logger.debug("Dispatching #{Enum.count(resource_ids)} ResourceUnavailableJob jobs")

    resource_ids
    |> Enum.map(fn resource_id ->
      %{resource_id: resource_id} |> Transport.Jobs.ResourceUnavailableJob.new()
    end)
    |> Oban.insert_all()

    :ok
  end

  def resources_to_check(false = _only_unavailable) do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id and d.is_active)
    |> where([r], not r.is_community_resource)
    |> where([r], like(r.url, "http%"))
    |> select([r], r.id)
    |> Repo.all()
  end

  def resources_to_check(true = _only_unavailable) do
    ResourceUnavailability
    |> where([r], is_nil(r.end))
    |> select([r], r.resource_id)
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
  alias DB.{Repo, Resource, ResourceUnavailability}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_id" => resource_id}}) do
    Logger.info("Running ResourceUnavailableJob for #{resource_id}")
    resource = Repo.get!(Resource, resource_id)

    resource |> check_availability() |> update_data(resource)
  end

  defp check_availability(%Resource{url: url}) do
    Transport.AvailabilityChecker.Wrapper.available?(url)
  end

  def update_data(false, %Resource{} = resource) do
    case ResourceUnavailability.ongoing_unavailability(resource) do
      nil ->
        %ResourceUnavailability{resource: resource, start: now()}
        |> Repo.insert!()

        :ok

      %ResourceUnavailability{} ->
        :ok
    end
  end

  def update_data(true, %Resource{} = resource) do
    case ResourceUnavailability.ongoing_unavailability(resource) do
      %ResourceUnavailability{} = resource_unavailability ->
        resource_unavailability
        |> Ecto.Changeset.change(%{end: now()})
        |> Repo.update!()

        :ok

      nil ->
        :ok
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
