defmodule TransportWeb.API.GTFSStopsControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "GET /api/gtfs-stops without parameters", %{conn: conn} do
    conn = conn |> get(~p"/api/gtfs-stops")
    json = json_response(conn, 422)
    assert json["error"] == "incorrect parameters"
  end

  test "GET /api/gtfs-stops with full map parameters", %{conn: conn} do
    conn =
      conn
      |> get(~p"/api/gtfs-stops", %{
        "south" => "48.8",
        "east" => "2.4",
        "west" => "2.2",
        "north" => "48.9",
        "width_pixels" => "1000",
        "height_pixels" => "1000",
        "zoom_level" => "12"
      })

    json = json_response(conn, 200)
    assert json["type"] == "FeatureCollection"
  end

  test "GET /api/gtfs-stops with a small zoom", %{conn: conn} do
    # At least one stop is needed to create the materialized view
    insert(:gtfs_stops, %{stop_lat: 48.8, stop_lon: 2.4})
    Transport.GTFSData.create_gtfs_stops_materialized_view(6)

    conn =
      conn
      |> get(~p"/api/gtfs-stops", %{
        "south" => "43.5326204268101",
        "east" => "22.6318359375",
        "west" => "-18.764648437500004",
        "north" => "49.724479188712984",
        "width_pixels" => "1884",
        "height_pixels" => "411",
        "zoom_level" => "6"
      })

    json = json_response(conn, 200)
    assert json["type"] == "clustered"
  end

  test "GET /api/gtfs-stops with only coordinate parameters", %{conn: conn} do
    insert(:gtfs_stops, %{stop_lat: 48.8, stop_lon: 2.4})

    conn =
      conn
      |> get(~p"/api/gtfs-stops", %{
        "south" => "48.8",
        "east" => "2.4",
        "west" => "2.2",
        "north" => "48.9"
      })

    json = json_response(conn, 200)
    assert json["type"] == "FeatureCollection"

    # Note: It’s not possible to test that the response is a GeoJSON (with a FeatureCollection) that matches the schema
  end
end
