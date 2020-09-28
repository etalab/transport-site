defmodule GBFS.VCubControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.ExternalCase
  alias GBFS.Router.Helpers, as: Routes

  @moduletag :external

  describe "test VCub GBFS conversion" do
    test "test gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.v_cub_path(conn, :index))
      body = json_response(conn, 200)
      assert Enum.all?(["version", "ttl", "last_updated", "data"], fn e -> e in Map.keys(body) end)
      assert Enum.count(body["data"]["fr"]["feeds"]) >= 3
    end

    test "test system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.v_cub_path(conn, :system_information))
      body = json_response(conn, 200)
      assert Enum.all?(["version", "ttl", "last_updated", "data"], fn e -> e in Map.keys(body) end)

      assert Enum.all?(["language", "name", "system_id", "timezone"], fn e ->
               e in Map.keys(body["data"])
             end)
    end

    test "test station_information.json", %{conn: conn} do
      use_cassette "vcub/station_information" do
        conn = conn |> get(Routes.v_cub_path(conn, :station_information))
        body = json_response(conn, 200)
        assert Enum.all?(["version", "ttl", "last_updated", "data"], fn e -> e in Map.keys(body) end)
        stations = body["data"]["stations"]
        assert Enum.count(stations) > 0

        station = Enum.at(stations, 0)

        assert Enum.all?(["capacity", "lat", "lon", "name", "post_code", "station_id"], fn e ->
                 e in Map.keys(station)
               end)

        assert station["capacity"] > 0
      end
    end

    test "test station_status.json", %{conn: conn} do
      use_cassette "vcub/station_status" do
        conn = conn |> get(Routes.v_cub_path(conn, :station_status))
        body = json_response(conn, 200)
        assert Enum.all?(["version", "ttl", "last_updated", "data"], fn e -> e in Map.keys(body) end)
        stations = body["data"]["stations"]
        assert Enum.count(stations) > 0

        station = Enum.at(stations, 0)

        assert Enum.all?(
                 [
                   "is_renting",
                   "is_returning",
                   "last_reported",
                   "num_bikes_available",
                   "num_docks_available",
                   "station_id"
                 ],
                 fn e ->
                   e in Map.keys(station)
                 end
               )

        assert station["num_docks_available"] >= 0 && station["num_docks_available"] < 1000
        assert station["num_bikes_available"] >= 0 && station["num_bikes_available"] < 1000
      end
    end
  end
end
