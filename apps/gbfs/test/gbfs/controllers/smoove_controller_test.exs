defmodule GBFS.SmooveControllerTest do
  use GBFS.ConnCase, async: true
  alias GBFS.Router.Helpers, as: Routes
  import Mox
  import GBFS.Checker

  setup :verify_on_exit!

  describe "Smoove GBFS conversion" do
    test "on gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.strasbourg_path(conn, :index))
      body = json_response(conn, 200)
      check_entrypoint(body)
    end

    test "on system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.strasbourg_path(conn, :system_information))
      body = json_response(conn, 200)
      check_system_information(body)
    end

    test "on station_information.json", %{conn: conn} do
      setup_stations_response()

      conn = conn |> get(Routes.strasbourg_path(conn, :station_information))
      body = json_response(conn, 200)
      check_station_information(body)
    end

    test "on station_status.json", %{conn: conn} do
      setup_stations_response()

      conn = conn |> get(Routes.strasbourg_path(conn, :station_status))
      body = json_response(conn, 200)
      check_station_status(body)
    end

    test "on invalid response", %{conn: conn} do
      Transport.HTTPoison.Mock |> expect(:get, fn _url -> {:ok, %HTTPoison.Response{status_code: 500}} end)

      conn = conn |> get(Routes.strasbourg_path(conn, :station_status))
      assert %{"error" => "smoove service unavailable"} == json_response(conn, 502)
    end

    defp setup_stations_response do
      Transport.HTTPoison.Mock
      |> expect(:get, fn url ->
        assert url == "http://velhop.strasbourg.eu/tvcstations.xml"

        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: """
            <vcs ver="1"><sl><si na="001 Rue Jules Ferry - Gare Saint-Roch" id="001" la="43.605366" lg="3.881346" av="5" fr="7" to="12"></si></sl></vcs>
           """,
           headers: [{"Content-Type", "application/xml"}]
         }}
      end)
    end
  end
end
