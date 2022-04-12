defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller

  def index(conn, %{"data" => "bnlc"}) do
    get_geojson = fn -> DB.GeoData.geo_data_as_geojson(2) end
    geojson = Transport.Cache.API.fetch(:bnlc_data, get_geojson)
    conn |> json(geojson)
  end
end
