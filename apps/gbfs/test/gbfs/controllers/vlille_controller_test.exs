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
                     "address" => "104-122 Bld VICTOR HUGO, LILLE",
                     "capacity" => 12,
                     "lat" => 50.62195,
                     "lon" => 3.06038,
                     "name" => "GANTOIS",
                     "station_id" => "788fb404ffb8978f726e8057c1b874e2cb37b941"
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
                     "is_installed" => true,
                     "is_renting" => true,
                     "is_returning" => true,
                     "last_reported" => 1_636_016_599,
                     "num_bikes_available" => 1,
                     "num_docks_available" => 11,
                     "station_id" => "788fb404ffb8978f726e8057c1b874e2cb37b941"
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
      assert url == "https://www.data.gouv.fr/fr/datasets/r/6d66af27-7a26-4263-b610-4ecf5fb34369"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
          [{"datasetid": "vlille-realtime", "recordid": "788fb404ffb8978f726e8057c1b874e2cb37b941", "fields": {"etat": "EN SERVICE", "etatconnexion": "CONNECTED", "nbvelosdispo": 1, "nbplacesdispo": 11, "commune": "LILLE", "type": "AVEC TPE", "libelle": 170, "datemiseajour": "2021-11-04T10:03:19+01:00", "localisation": [50.62195, 3.06038], "nom": "GANTOIS", "adresse": "104-122 Bld VICTOR HUGO", "geo": [50.62195, 3.06038]}, "geometry": {"type": "Point", "coordinates": [3.06038, 50.62195]}, "record_timestamp": "2021-11-04T10:06:03.610+01:00"}]
         """,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)
  end
end
