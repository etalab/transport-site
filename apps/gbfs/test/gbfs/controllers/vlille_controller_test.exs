defmodule GBFS.VlilleControllerTest do
  use GBFS.ConnCase, async: true
  alias GBFS.Router.Helpers, as: Routes
  import Mox
  import GBFS.Checker

  setup :verify_on_exit!

  describe "VLille GBFS conversion" do
    test "on gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.v_lille_path(conn, :index))
      body = json_response(conn, 200)
      check_entrypoint(body)
    end

    test "on system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.v_lille_path(conn, :system_information))
      body = json_response(conn, 200)
      check_system_information(body)
    end

    test "on station_information.json", %{conn: conn} do
      setup_stations_response()
      conn = conn |> get(Routes.v_lille_path(conn, :station_information))
      body = json_response(conn, 200)

      check_station_information(body)

      assert %{
               "data" => %{
                 "stations" => [
                   %{
                     "address" => "ROND POINT DE L'EUROPE, ROUBAIX",
                     "capacity" => 10,
                     "lat" => 50.689762,
                     "lon" => 3.177179,
                     "name" => "MOTTE BOSSUT",
                     "station_id" => 231
                   }
                 ]
               },
               "ttl" => 60,
               "version" => "2.0"
             } = body
    end

    test "on station_status.json", %{conn: conn} do
      setup_stations_response()
      conn = conn |> get(Routes.v_lille_path(conn, :station_status))
      body = json_response(conn, 200)

      check_station_status(body)

      assert %{
               "data" => %{
                 "stations" => [
                   %{
                     "is_installed" => false,
                     "is_renting" => false,
                     "is_returning" => false,
                     "last_reported" => 1_669_715_236,
                     "num_bikes_available" => 0,
                     "num_docks_available" => 10,
                     "station_id" => 231
                   }
                 ]
               },
               "ttl" => 60,
               "version" => "2.0"
             } = body
    end

    test "on invalid VLille response", %{conn: conn} do
      Transport.HTTPoison.Mock |> expect(:get, fn _url, _, _ -> {:ok, %HTTPoison.Response{status_code: 500}} end)

      conn = conn |> get(Routes.v_lille_path(conn, :station_status))
      assert %{"error" => "VLille service unavailable"} == json_response(conn, 502)
    end
  end

  defp setup_stations_response do
    Transport.HTTPoison.Mock
    |> expect(:get, fn url, [], hackney: [follow_redirect: true] ->
      assert url == "https://www.data.gouv.fr/fr/datasets/r/ee846604-5a31-4ac5-b536-9069fa2e3791"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
          [{"libelle": 231, "nom": "MOTTE BOSSUT", "adresse": "ROND POINT DE L'EUROPE", "commune": "ROUBAIX", "etat": "EN SERVICE", "type": "AVEC TPE", "geo": {"lon": 3.177179, "lat": 50.689762}, "nbplacesdispo": 10, "nbvelosdispo": 0, "etatconnexion": "D\u00c9CONNECT\u00c9", "localisation": {"lon": 3.177179, "lat": 50.689762}, "datemiseajour": "2022-11-29T09:47:16+00:00"}]
         """,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)
  end
end
