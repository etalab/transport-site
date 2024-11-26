defmodule DB.GeoDataImport do
  @moduledoc """
  Links geo_data data with its source
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "geo_data_import" do
    belongs_to(:resource_history, DB.ResourceHistory)
    field(:slug, Ecto.Enum, values: Transport.ConsolidatedDataset.geo_data_datasets() ++ [:gbfs_stations])
    has_many(:geo_data, DB.GeoData)

    timestamps(type: :utc_datetime_usec)
  end
end
