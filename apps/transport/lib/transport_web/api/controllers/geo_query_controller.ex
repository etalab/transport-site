defmodule TransportWeb.API.GeoQueryController do
  use TransportWeb, :controller

  def index(conn, %{"data" => "bnlc"}) do
    geojson = DB.GeoData.geo_data_as_geojson(2)
    conn |> json(geojson)
  end
end
