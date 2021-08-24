defmodule GBFS.VCubControllerTest do
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  alias GBFS.Router.Helpers, as: Routes
  import Mock
  import GBFS.Checker

  describe "test VCub GBFS conversion" do
    test "test gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.v_cub_path(conn, :index))
      body = json_response(conn, 200)
      check_entrypoint(body)
    end

    test "test system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.v_cub_path(conn, :system_information))
      body = json_response(conn, 200)
      check_system_information(body)
    end

    test "test station_information.json", %{conn: conn} do
      use_cassette "vcub/station_information" do
        conn = conn |> get(Routes.v_cub_path(conn, :station_information))
        body = json_response(conn, 200)
        check_station_information(body)

        stations = body["data"]["stations"]
        assert Enum.count(stations) > 0

        station = Enum.at(stations, 0)
        assert station["post_code"] == "33063"
      end
    end

    test "test station_status.json", %{conn: conn} do
      use_cassette "vcub/station_status" do
        conn = conn |> get(Routes.v_cub_path(conn, :station_status))
        body = json_response(conn, 200)
        check_station_status(body)
      end
    end

    test "test invalid vcub response", %{conn: conn} do
      mock = fn "https://opendata.bordeaux-metropole.fr/api/records/1.0/search/?dataset=ci_vcub_p&q=&rows=10000" ->
        {:ok, %HTTPoison.Response{body: "{}", status_code: 500}}
      end

      with_mock HTTPoison, get: mock do
        conn = conn |> get(Routes.v_cub_path(conn, :station_status))
        assert %{"error" => "service vcub unavailable"} == json_response(conn, 502)

        assert_called_exactly(HTTPoison.get(:_), 1)
      end
    end
  end
end
