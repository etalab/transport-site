defmodule Transport.Jobs.DatasetHistoryDispatcherJob do
  @moduledoc """
  Job in charge of dispatching multiple `DatasetHistoryJob`
  """
  use Oban.Worker, unique: [period: {20, :hours}], tags: ["history"], max_attempts: 3
  require Logger
  import Ecto.Query

  @impl Oban.Worker
  def perform(_job) do
    DB.Dataset.base_with_hidden_datasets()
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
    unique: [period: {20, :hours}, fields: [:args, :queue, :worker]],
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
      payload: %{
        "licence" => dataset.licence,
        "type" => dataset.type,
        "slug" => dataset.slug,
        "custom_tags" => dataset.custom_tags
      },
      dataset_history_resources:
        dataset.resources
        |> Enum.map(fn resource ->
          {resource_history_id, last_up_to_date_at} =
            case resource.resource_history do
              [%{id: id, last_up_to_date_at: last_up_to_date_at}] -> {id, last_up_to_date_at}
              [] -> {nil, nil}
            end

          resource_metadata_id =
            case resource.resource_metadata do
              [%{id: id}] -> id
              [] -> nil
            end

          resource_validation_id =
            case resource.validations do
              [%{id: id}] -> id
              [] -> nil
            end

          %DB.DatasetHistoryResources{
            resource_id: resource.id,
            resource_history_id: resource_history_id,
            resource_history_last_up_to_date_at: last_up_to_date_at,
            resource_metadata_id: resource_metadata_id,
            validation_id: resource_validation_id,
            payload: %{
              url: resource.url,
              latest_url: resource.latest_url,
              download_url: DB.Resource.download_url(resource)
            },
            resource_datagouv_id: resource.datagouv_id
          }
        end)
    }
    |> DB.Repo.insert!()

    :ok
  end

  def get_preloaded_dataset(dataset_id) do
    latest_resource_metadata =
      DB.ResourceMetadata |> distinct([rm], rm.resource_id) |> order_by([rm], asc: rm.resource_id, desc: rm.inserted_at)

    # could be problematic if multiple validators are used for the same real time resource
    latest_resource_validation =
      DB.MultiValidation |> distinct([mv], mv.resource_id) |> order_by([mv], asc: mv.resource_id, desc: mv.inserted_at)

    DB.Dataset.base_with_hidden_datasets()
    |> where([dataset: d], d.id == ^dataset_id)
    |> join(:left, [dataset: d], r in DB.Resource, on: d.id == r.dataset_id, as: :resource)
    |> join(:left, [resource: r], rh in DB.ResourceHistory,
      on: rh.resource_id == r.id,
      as: :resource_history
    )
    |> distinct([resource: r], r.id)
    |> order_by([resource: r, resource_history: rh],
      asc: r.id,
      desc: rh.inserted_at
    )
    |> preload([resource: r, resource_history: rh, dataset: d],
      resources:
        {r,
         dataset: d,
         resource_history: rh,
         resource_metadata: ^latest_resource_metadata,
         validations: ^latest_resource_validation}
    )
    |> DB.Repo.one!()
  end
end
