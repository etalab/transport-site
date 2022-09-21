defmodule TransportWeb.GbfsToGeojsonController do
  use TransportWeb, :controller
  alias Transport.GbfsToGeojson

  plug(CORSPlug, origin: "*", expose: ["*"], credentials: false)

  def convert(conn, %{"url" => gbfs_url} = params) do
    resp = GbfsToGeojson.gbfs_geojsons(gbfs_url, params)
    conn |> json(resp)
  end
end
