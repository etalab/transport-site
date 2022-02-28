defmodule DB.GtfsStops do
  @moduledoc """
  This contains the information present in GTFS stops.txt files.
  https://developers.google.com/transit/gtfs/reference?hl=fr#stopstxt
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_stops" do
    belongs_to(:data_import, DB.GtfsImport)
    field(:stop_id, :binary)
    field(:stop_name, :binary)
    field(:stop_lat, :float)
    field(:stop_lon, :float)
    field(:location_type, :integer)
  end
end
