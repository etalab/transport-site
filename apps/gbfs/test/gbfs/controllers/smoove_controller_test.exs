defmodule GBFS.SmooveControllerTest do
  use GBFS.ConnCase, async: false
  alias GBFS.Router.Helpers, as: Routes
  use GBFS.ExternalCase
  # import Mock
  import GBFS.Checker

  describe "Smoove GBFS conversion" do
    test "on gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.montpellier_path(conn, :index))
      body = json_response(conn, 200)
      check_entrypoint(body)
    end

    test "on system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.montpellier_path(conn, :system_information))
      body = json_response(conn, 200)
      check_system_information(body)
    end

    test "on station_information.json", %{conn: conn} do
      use_cassette "smoove/stations" do
        conn = conn |> get(Routes.montpellier_path(conn, :station_information))
        body = json_response(conn, 200)
        check_station_information(body)
      end
    end

    test "on station_status.json", %{conn: conn} do
      use_cassette "smoove/stations" do
        conn = conn |> get(Routes.montpellier_path(conn, :station_status))
        body = json_response(conn, 200)
        check_station_status(body)
      end
    end
  end
end
