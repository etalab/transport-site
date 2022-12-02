defmodule Transport.Jobs.DatasetHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `DatasetHistoryJob`
  """
  use Oban.Worker, unique: [period: 60 * 60 * 5], tags: ["history"], max_attempts: 3
  require Logger
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    DB.Dataset.base_query()
    |> DB.Repo.all()
    |> Enum.map(fn dataset ->
      %{dataset_id: dataset.id} |> Transport.Jobs.DatasetHistoryJob.new()
    end)
    |> Oban.insert_all()

    :ok
  end
end

defmodule Transport.Jobs.DatasetHistoryJob do
  @moduledoc """
  Job historicising a single dataset
  """
  use Oban.Worker,
    unique: [period: 60 * 60 * 5, fields: [:args, :queue, :worker]],
    tags: ["history"],
    max_attempts: 3

  require Logger
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"dataset_id" => dataset_id}}) do
    Logger.info("Running DatasetHistoryJob for dataset##{dataset_id}")

    dataset = get_preloaded_dataset(dataset_id)

    %DB.DatasetHistory{
      dataset_id: dataset_id,
      dataset_datagouv_id: dataset.datagouv_id,
      timestamp: DateTime.utc_now(),
      payload: %{"licence" => dataset.licence, "type" => dataset.type, "slug" => dataset.slug},
      dataset_history_resources:
        dataset.resources
        |> Enum.map(fn resource ->
          resource_history_id =
            case resource.resource_history do
              [%{id: id}] -> id
              [] -> nil
            end

          resource_metadata_id =
            case resource.resource_metadata do
              [%{id: id}] -> id
              [] -> nil
            end

          %DB.DatasetHistoryResources{
            resource_id: resource.id,
            resource_history_id: resource_history_id,
            resource_metadata_id: resource_metadata_id,
            payload: %{
              url: resource.url,
              latest_url: resource.latest_url,
              download_url: DB.Resource.download_url(resource)
            }
          }
        end)
    }
    |> DB.Repo.insert!()

    :ok
  end

  def get_preloaded_dataset(dataset_id) do
    DB.Dataset.base_query()
    |> where([dataset: d], d.id == ^dataset_id)
    |> DB.Resource.join_dataset_with_resource()
    |> join(:left, [resource: r], rh in DB.ResourceHistory,
      on: rh.resource_id == r.id,
      as: :resource_history
    )
    |> join(:left, [resource: r], rm in DB.ResourceMetadata,
      on: rm.resource_id == r.id,
      as: :resource_metadata
    )
    |> distinct([resource: r], r.id)
    |> order_by([resource: r, resource_history: rh, resource_metadata: rm],
      asc: r.id,
      desc: rh.inserted_at,
      desc: rm.inserted_at
    )
    |> preload([resource: r, resource_history: rh, resource_metadata: rm],
      resources: {r, resource_history: rh, resource_metadata: rm}
    )
    |> DB.Repo.one!()
  end
end
