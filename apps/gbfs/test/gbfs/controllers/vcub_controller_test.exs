defmodule GBFS.VCubControllerTest do
  use GBFS.ConnCase, async: true
  alias GBFS.Router.Helpers, as: Routes
  import Mox
  import GBFS.Checker

  setup :verify_on_exit!

  describe "VCub GBFS conversion" do
    test "on gbfs.json", %{conn: conn} do
      conn = conn |> get(Routes.v_cub_path(conn, :index))
      body = json_response(conn, 200)
      check_entrypoint(body)
    end

    test "on system_information.json", %{conn: conn} do
      conn = conn |> get(Routes.v_cub_path(conn, :system_information))
      body = json_response(conn, 200)
      check_system_information(body)
    end

    test "on station_information.json", %{conn: conn} do
      setup_stations_response()
      conn = conn |> get(Routes.v_cub_path(conn, :station_information))
      body = json_response(conn, 200)

      check_station_information(body)

      assert %{
               "data" => %{
                 "stations" => [
                   %{
                     "capacity" => 41,
                     "lat" => 44.823285,
                     "lon" => -0.554574,
                     "name" => "Belcier Gare",
                     "station_id" => "251",
                     "post_code" => "33063"
                   }
                 ]
               },
               "ttl" => 60,
               "version" => "2.0"
             } = body
    end

    test "on station_status.json", %{conn: conn} do
      setup_stations_response()
      conn = conn |> get(Routes.v_cub_path(conn, :station_status))
      body = json_response(conn, 200)

      check_station_status(body)

      assert %{
               "data" => %{
                 "stations" => [
                   %{
                     "is_installed" => true,
                     "is_renting" => true,
                     "is_returning" => true,
                     "last_reported" => 1_636_026_224,
                     "num_bikes_available" => 21,
                     "num_docks_available" => 20,
                     "station_id" => "251"
                   }
                 ]
               },
               "ttl" => 60,
               "version" => "2.0"
             } = body
    end

    test "on invalid VCub response", %{conn: conn} do
      Transport.HTTPoison.Mock |> expect(:get, fn _url -> {:ok, %HTTPoison.Response{status_code: 500}} end)

      conn = conn |> get(Routes.v_cub_path(conn, :station_status))
      assert %{"error" => "VCub service unavailable"} == json_response(conn, 502)
    end
  end

  defp setup_stations_response do
    Transport.HTTPoison.Mock
    |> expect(:get, fn url ->
      assert url == "https://opendata.bordeaux-metropole.fr/api/records/1.0/search/?dataset=ci_vcub_p&q=&rows=10000"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: """
          {"records":[{"datasetid": "ci_vcub_p", "recordid": "ffcbc65cda51e817fd9a161a493a4eba570b012e", "fields": {"etat": "CONNECTEE", "commune": "Bordeaux", "ident": 251, "mdate": "2021-11-04T11:43:44+00:00", "nom": "Belcier Gare", "nbclassiq": "15", "code_commune": "33063", "gml_id": "CI_VCUB_P.251", "geo_point_2d": [44.823285, -0.554574], "nbplaces": 20, "cdate": "2011-01-01T00:00:00+00:00", "gid": 251, "geom_o": "0", "geo_shape": {"type": "Point", "coordinates": [-0.554574, 44.823285]}, "nbelec": "6", "nbvelos": 21, "type": "VLS"}, "geometry": {"type": "Point", "coordinates": [-0.554574, 44.823285]}, "record_timestamp": "2021-11-04T10:45:28.094000+00:00"}]}
         """,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)
  end
end
