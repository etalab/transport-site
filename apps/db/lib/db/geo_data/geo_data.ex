defmodule DB.GeoData do
  @moduledoc """
  Stores any kind of geographical data, typically from a resource
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "geo_data" do
    field(:geom, Geo.PostGIS.Geometry) :: Geo.geometry()
    field(:payload, :map)
    belongs_to(:geo_data_import, DB.GeoDataImport)
  end

  def geo_data_as_geojson(%{id: geo_data_import_id}) do
    subquery = from g in DB.GeoData, where: g.geo_data_import_id == ^geo_data_import_id, select: %{geom: g.geom, nom_lieu: fragment("payload->>'nom_lieu'")}

    query =
      from(g in subquery(subquery),
        select:
          fragment(
            "json_build_object('type', 'FeatureCollection', 'features', json_agg(ST_AsGeoJSON(?)::json))",
            g
          )
      )

    query |> DB.Repo.one()
  end
end
