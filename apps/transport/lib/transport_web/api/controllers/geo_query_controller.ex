defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller
  import Ecto.Query

  def index(conn, %{"data" => "bnlc"}) do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    get_geojson = fn ->
      %{id: id} =
        DB.Dataset
        |> where([d], d.type == "carpooling-areas" and d.organization == ^transport_publisher_label)
        |> DB.Repo.one!()

      id
      |> DB.GeoDataImport.dataset_latest_geo_data_import()
      |> geo_data_as_bnlc_geojson()
    end

    geojson = Transport.Cache.API.fetch(:bnlc_data, get_geojson, :timer.hours(1))
    conn |> json(geojson)
  end

  def geo_data_as_bnlc_geojson(geo_data_import) do
    add_bnlc_fields = fn query -> from(g in query, select_merge: %{nom_lieu: fragment("payload->>'nom_lieu'")}) end
    DB.GeoData.geo_data_as_geojson(geo_data_import, add_bnlc_fields)
  end
end
