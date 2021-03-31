defmodule GBFS.JCDecauxControllerTest do
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  alias GBFS.Router.Helpers, as: Routes
  import Mock
  import GBFS.Checker

  @moduletag :external

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
      use_cassette "jcdecaux/station_information" do
        conn = conn |> get(Routes.toulouse_path(conn, :station_information))
        body = json_response(conn, 200)
        check_station_information(body)
      end
    end

    test "on station_status.json", %{conn: conn} do
      use_cassette "jcdecaux/station_status" do
        conn = conn |> get(Routes.toulouse_path(conn, :station_status))
        body = json_response(conn, 200)
        check_station_status(body)
      end
    end

    test "on invalid jcdecaux response", %{conn: conn} do
      mock = fn url ->
        if String.match?(url, ~r|https://api.jcdecaux.com/vls/v1.*|) do
          {:ok, %HTTPoison.Response{body: "{}", status_code: 500}}
        end
      end

      with_mock HTTPoison, get: mock do
        conn = conn |> get(Routes.toulouse_path(conn, :station_status))
        assert %{"error" => "jcdecaux service unavailable"} == json_response(conn, 502)

        assert_called_exactly(HTTPoison.get(:_), 1)
      end
    end
  end
end
