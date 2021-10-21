defmodule GBFS.JCDecauxControllerTest do
  use GBFS.ConnCase, async: false
  alias GBFS.Router.Helpers, as: Routes
  import Mox
  import GBFS.Checker

  setup :verify_on_exit!

  describe "JCDecaux GBFS conversion" do
    test "on gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.toulouse_path(conn, :index))
      body = json_response(conn, 200)
      check_entrypoint(body)
    end

    test "on system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.toulouse_path(conn, :system_information))
      body = json_response(conn, 200)
      check_system_information(body)
    end

    test "on station_information.json", %{conn: conn} do
      setup_stations_response()
      conn = conn |> get(Routes.toulouse_path(conn, :station_information))
      body = json_response(conn, 200)
      check_station_information(body)
    end

    test "on station_status.json", %{conn: conn} do
      setup_stations_response()
      conn = conn |> get(Routes.toulouse_path(conn, :station_status))
      body = json_response(conn, 200)
      check_station_status(body)
    end

    test "on invalid jcdecaux response", %{conn: conn} do
      Transport.HTTPoison.Mock |> expect(:get, fn _url -> {:ok, %HTTPoison.Response{status_code: 500}} end)

      conn = conn |> get(Routes.toulouse_path(conn, :station_status))
      assert %{"error" => "jcdecaux service unavailable"} == json_response(conn, 502)
    end
  end

  defp setup_stations_response do
    Transport.HTTPoison.Mock
    |> expect(:get, fn url ->
      assert String.starts_with?(url, "https://api.jcdecaux.com/vls/v1/stations?contract=toulouse")

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
          [{"number":55,"contract_name":"toulouse","name":"00055 - ST SERNIN G. ARNOULT","address":"2 RUE GATIEN ARNOULT","position":{"lat":43.608951960496405,"lng":1.441003598726198},"banking":true,"bonus":false,"bike_stands":15,"available_bike_stands":4,"available_bikes":10,"status":"OPEN","last_update":1608112351000}]
         """,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)
  end
end
