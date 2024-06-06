defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller
  import Ecto.Query

  def index(%Plug.Conn{} = conn, %{"data" => slug}) do
    if Map.has_key?(config(), slug) do
      %{dataset: %DB.Dataset{} = dataset, transform_fn: transform_fn} = Map.fetch!(config(), slug)

      get_geojson = fn ->
        dataset
        |> Map.fetch!(:id)
        |> DB.GeoDataImport.dataset_latest_geo_data_import()
        |> transform_fn.()
      end

      geojson = Transport.Cache.fetch("#{slug}_data", get_geojson, :timer.hours(1))
      conn |> json(geojson)
    else
      render_404(conn)
    end
  end

  def index(%Plug.Conn{} = conn, _), do: render_404(conn)

  def render_404(%Plug.Conn{} = conn), do: conn |> put_status(404) |> json(%{"message" => "Not found"})

  defp config do
    %{
      "bnlc" => %{dataset: Transport.Jobs.BNLCToGeoData.relevant_dataset(), transform_fn: &bnlc_geojson/1},
      "parkings-relais" => %{
        dataset: Transport.Jobs.ParkingsRelaisToGeoData.relevant_dataset(),
        transform_fn: &parkings_relais_geojson/1
      },
      "zfe" => %{
        dataset: Transport.Jobs.LowEmissionZonesToGeoData.relevant_dataset(),
        transform_fn: &zfe_geojson/1
      },
      "irve" => %{
        dataset: Transport.Jobs.IRVEToGeoData.relevant_dataset(),
        transform_fn: &irve_geojson/1
      }
    }
  end

  def bnlc_geojson(%DB.GeoDataImport{} = geo_data_import) do
    add_fields = fn query -> from(g in query, select_merge: %{nom_lieu: fragment("payload->>'nom_lieu'")}) end
    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def parkings_relais_geojson(%DB.GeoDataImport{} = geo_data_import) do
    add_fields = fn query ->
      from(g in query,
        select_merge: %{nom: fragment("payload->>'nom'"), nb_pr: fragment("(payload->>'nb_pr')::int")}
      )
    end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def zfe_geojson(%DB.GeoDataImport{} = geo_data_import) do
    add_fields = fn query -> query end

    DB.GeoData.geo_data_as_geojson(geo_data_import, add_fields)
  end

  def irve_geojson(%DB.GeoDataImport{} = geo_data_import) do
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
