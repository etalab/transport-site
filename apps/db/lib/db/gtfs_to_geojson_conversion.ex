defmodule DB.GtfsToGeojsonConversion do
  @moduledoc """
  GtfsToGeojsonConversion stores metadata for GTFS to GeoJSONs conversions
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_to_geojson_conversion" do
    field(:datagouv_id, :string)
    field(:resource_history_uuid, :string)
    field(:payload, :map)

    timestamps(type: :utc_datetime_usec)
  end


end
