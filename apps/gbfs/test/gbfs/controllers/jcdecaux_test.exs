defmodule GBFS.JCDecauxControllerTest do
  use GBFS.ConnCase, async: false
  use GBFS.ExternalCase
  alias GBFS.Router.Helpers, as: Routes
  import Mock
  import AppConfigHelper
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

    @tag :pouet
    test "on invalid jcdecaux response", %{conn: conn} do
      mock = fn url ->
        if String.match?(url, ~r|https://api.jcdecaux.com/vls/v1.*|) do
          {:ok, %HTTPoison.Response{body: "{}", status_code: 500}}
        end
      end

      # we also mock Sentry, but using bypass since we don't want to mock sentry's internal
      bypass = Bypass.open()

      Bypass.expect(bypass, fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)
        Plug.Conn.resp(conn, 200, ~s<{"id": "340"}>)
      end)

      change_app_config_temporarily(:sentry, :dsn, "http://public:secret@localhost:#{bypass.port}/1")
      change_app_config_temporarily(:sentry, :included_environments, [:test])

      with_mock HTTPoison, get: mock do
        conn = conn |> get(Routes.toulouse_path(conn, :station_status))
        assert %{"error" => "service jcdecaux unavailable"} == json_response(conn, 502)

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
