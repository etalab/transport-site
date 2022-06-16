defmodule DB.ResourceHistory do
  @moduledoc """
  ResourceHistory stores metadata when resources are historicized.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  @derive {Jason.Encoder, only: [:resource_id, :payload, :last_up_to_date_at, :inserted_at, :updated_at]}
  typed_schema "resource_history" do
    field(:datagouv_id, :string)
    field(:payload, :map)
    # the last moment we checked and the resource history was corresponding to the real online resource
    field(:last_up_to_date_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
    belongs_to(:resource, DB.Resource)
    has_many(:geo_data_import, DB.GeoDataImport)
    has_many(:validations, DB.MultiValidation)
    has_many(:metadata, DB.ResourceMetadata)
  end

  def base_query, do: from(rh in DB.ResourceHistory, as: :resource_history)

  def join_resource_with_latest_resource_history(query) do
    last_resource_history =
      DB.ResourceHistory
      |> where([rh], rh.resource_id == parent_as(:resource).id)
      |> order_by([rh], desc: :inserted_at)
      |> select([rh], rh.id)
      |> limit(1)

    query
    |> join(:inner, [resource: r], rh in DB.ResourceHistory, on: rh.resource_id == r.id, as: :resource_history)
    |> join(:inner_lateral, [resource_history: rh], latest in subquery(last_resource_history), on: latest.id == rh.id)
  end

  defp latest_resource_history_query(resource_id) do
    DB.ResourceHistory
    |> where([rh], rh.resource_id == ^resource_id)
    |> order_by([rh], desc: rh.inserted_at)
    |> limit(1)
  end

  def latest_resource_history(%DB.Resource{id: id}), do: latest_resource_history(id)

  def latest_resource_history(resource_id) do
    resource_id
    |> latest_resource_history_query
    |> DB.Repo.one()
  end

  def latest_resource_history_payload(resource_id) do
    resource_id
    |> latest_resource_history_query
    |> select([rh], rh.payload)
    |> DB.Repo.one()
  end

  def latest_resource_history_infos(resource_id) do
    resource_id
    |> latest_resource_history_payload()
    |> case do
      %{"permanent_url" => url, "filesize" => filesize} -> %{url: url, filesize: filesize}
      _ -> nil
    end
  end

  @spec latest_dataset_resources_history_infos(integer()) :: map()
  def latest_dataset_resources_history_infos(dataset_id) do
    DB.Resource.base_query()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> where([resource: r], r.dataset_id == ^dataset_id)
    |> select(
      [resource: r, resource_history: rh],
      {r.id, %{url: fragment("payload->>'permanent_url'"), filesize: fragment("payload->>'filesize'")}}
    )
    |> DB.Repo.all()
    |> Enum.into(%{})
  end
end
