defmodule DB.GeoDataImport do
  @moduledoc """
  Links geo_data data with its source
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "geo_data_import" do
    belongs_to(:resource_history, DB.ResourceHistory)
    has_many(:geo_data, DB.GeoData)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  takes a dataset_id as input, return the latest geo_data_import done for that dataset
  """
  def dataset_latest_geo_data_import(dataset_id) do
    DB.ResourceHistory
    |> join(:inner, [rh], g in DB.GeoDataImport, on: rh.id == g.resource_history_id)
    |> where([rh, _g], fragment("(payload->>'dataset_id')::bigint") == ^dataset_id)
    |> order_by([rh, _g], desc: rh.inserted_at)
    |> limit(1)
    |> select([_rh, g], g)
    |> DB.Repo.one()
  end
end
