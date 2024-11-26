defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller
  import Ecto.Query

  @possible_slugs Ecto.Enum.dump_values(DB.GeoDataImport, :slug)

  def index(%Plug.Conn{} = conn, %{"data" => slug}) when slug in @possible_slugs do
    case DB.Repo.get_by(DB.GeoDataImport, slug: slug) do
      nil ->
        render_404(conn)

      %DB.GeoDataImport{} = geo_data_import ->
        get_geojson = fn -> transform_geojson(geo_data_import, String.to_existing_atom(slug)) end
        geojson = Transport.Cache.fetch("#{slug}_data", get_geojson, :timer.hours(1))
        conn |> json(geojson)
    end
  end

  def index(%Plug.Conn{} = conn, _), do: render_404(conn)

  def render_404(%Plug.Conn{} = conn), do: conn |> put_status(404) |> json(%{"message" => "Not found"})

  def transform_geojson(%DB.GeoDataImport{} = geo_data_import, :bnlc) do
    add_fields = fn query -> from(g in query, select_merge: %{nom_lieu: fragment("payload->>'nom_lieu'")}) end
    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def transform_geojson(%DB.GeoDataImport{} = geo_data_import, :parkings_relais) do
    add_fields = fn query ->
      from(g in query,
        select_merge: %{nom: fragment("payload->>'nom'"), nb_pr: fragment("(payload->>'nb_pr')::int")}
      )
    end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def transform_geojson(%DB.GeoDataImport{} = geo_data_import, :zfe) do
    add_fields = fn query -> query end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def transform_geojson(%DB.GeoDataImport{} = geo_data_import, :irve) do
    add_fields = fn query ->
      from(g in query,
        select_merge: %{
          nom_enseigne: fragment("payload->>'nom_enseigne'"),
          id_station_itinerance: fragment("payload->>'id_station_itinerance'"),
          nom_station: fragment("payload->>'nom_station'"),
          nbre_pdc: fragment("payload->>'nbre_pdc'")
        }
      )
    end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def transform_geojson(%DB.GeoDataImport{} = geo_data_import, :gbfs_stations) do
    add_fields = fn query ->
      from(g in query,
        select_merge: %{capacity: fragment("payload->>'capacity'"), name: fragment("payload->>'name'")}
      )
    end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end
end
