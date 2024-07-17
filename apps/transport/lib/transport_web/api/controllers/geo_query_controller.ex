defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller
  import Ecto.Query

  def index(%Plug.Conn{} = conn, %{"data" => slug}) do
    feature_atom = slug |> String.to_atom()

    if feature_atom in Transport.ConsolidatedDataset.geo_data_datasets() do
      dataset = Transport.ConsolidatedDataset.dataset(feature_atom)

      get_geojson = fn ->
        dataset
        |> Map.fetch!(:id)
        |> DB.GeoDataImport.dataset_latest_geo_data_import()
        |> transform_geojson(feature_atom)
      end

      geojson = Transport.Cache.fetch("#{slug}_data", get_geojson, :timer.hours(1))
      conn |> json(geojson)
    else
      render_404(conn)
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
end
