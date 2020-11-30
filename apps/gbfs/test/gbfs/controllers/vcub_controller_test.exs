defmodule GBFS.VCubControllerTest do
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  alias GBFS.Router.Helpers, as: Routes
  import Mock
  import AppConfigHelper

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

    test "test invalid vcub response", %{conn: conn} do
      mock = fn "https://opendata.bordeaux-metropole.fr/api/records/1.0/search/?dataset=ci_vcub_p&q=&rows=10000" ->
        {:ok, %HTTPoison.Response{body: "{}", status_code: 500}}
      end

      # we also mock Sentry, but using bypass since we don't want to mock sentry's internal
      bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)
        Plug.Conn.resp(conn, 200, ~s<{"id": "340"}>)
      end)

      change_app_config_temporarily(:sentry, :dsn, "http://public:secret@localhost:#{bypass.port}/1")

      with_mock HTTPoison, get: mock do
        conn = conn |> get(Routes.v_cub_path(conn, :station_status))
        assert %{"error" => "service vcub unavailable"} == json_response(conn, 502)

        # Sentry 0.7 does not have a sync mode, so the message is send asynchronously,
        # we wait to be sure that the message is send.
        # in Sentry 0.8 we'll be able to do:
        # change_app_config_temporarily(:sentry, :send_result, :sync)
        :timer.sleep(500)

        assert_called_exactly(HTTPoison.get(:_), 1)
      end
    end
  end
end
