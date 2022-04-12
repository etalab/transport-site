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
      |> DB.GeoData.geo_data_as_geojson()
    end

    geojson = Transport.Cache.API.fetch(:bnlc_data, get_geojson)
    conn |> json(geojson)
  end
end
