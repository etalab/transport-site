defmodule DB.GeoData do
  @moduledoc """
  Stores any kind of geographical data, typically from a resource
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "geo_data" do
    field(:geom, Geo.PostGIS.Geometry)
    field(:payload, :map)
    belongs_to(:geo_data_import, DB.GeoDataImport)
  end
end
