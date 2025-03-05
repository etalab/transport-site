defmodule DB.ResourceHistory do
  @moduledoc """
  ResourceHistory stores metadata when resources are historicized.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  @derive {Jason.Encoder, only: [:resource_id, :payload, :last_up_to_date_at, :inserted_at, :updated_at]}
  typed_schema "resource_history" do
    # `datagouv_id` is `null` for reuser improved data and filled for resources
    field(:datagouv_id, :string)
    field(:payload, :map)
    # the last moment we checked and the resource history was corresponding to the real online resource
    field(:last_up_to_date_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
    belongs_to(:resource, DB.Resource)
    belongs_to(:reuser_improved_data, DB.ReuserImprovedData)
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

  def join_dataset_with_latest_resource_history(query) do
    query
    |> join(:inner, [dataset: d], r in DB.Resource, on: r.dataset_id == d.id, as: :resource)
    |> join_resource_with_latest_resource_history()
  end

  defp latest_resource_history_query(resource_id) do
    DB.ResourceHistory
    |> where([rh], rh.resource_id == ^resource_id)
    |> order_by([rh], desc: rh.inserted_at)
    |> limit(1)
  end

  @spec latest_resource_history(DB.Resource.t() | integer()) :: DB.ResourceHistory.t() | nil
  def latest_resource_history(%DB.Resource{id: id}), do: latest_resource_history(id)

  def latest_resource_history(resource_id) do
    resource_id
    |> latest_resource_history_query
    |> DB.Repo.one()
  end

  @spec latest_dataset_resources_history_infos(DB.Dataset.t()) :: %{integer() => DB.ResourceHistory.t()}
  def latest_dataset_resources_history_infos(%DB.Dataset{id: dataset_id}) do
    DB.Resource.base_query()
    |> DB.ResourceHistory.join_resource_with_latest_resource_history()
    |> DB.Resource.filter_on_dataset_id(dataset_id)
    |> select([resource: r, resource_history: rh], {r.id, rh})
    |> DB.Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  iex> gtfs_flex?(%DB.ResourceHistory{payload: %{"format" => "GTFS", "filenames" => ["stops.txt", "booking_rules.txt"]}})
  true
  iex> gtfs_flex?(%DB.ResourceHistory{payload: %{"format" => "GTFS", "filenames" => ["stops.txt", "locations.geojson"]}})
  true
  iex> gtfs_flex?(%DB.ResourceHistory{payload: %{"format" => "GTFS", "filenames" => ["stops.txt"]}})
  false
  """
  @spec gtfs_flex?(DB.ResourceHistory.t()) :: boolean()
  def gtfs_flex?(%__MODULE__{payload: %{"format" => "GTFS", "filenames" => filenames}}) do
    # See https://gtfs.org/extensions/flex/ and search for "Add new file"
    Enum.any?(filenames, &(&1 in ["booking_rules.txt", "locations.geojson"]))
  end

  def gtfs_flex?(%__MODULE__{}), do: false
end
