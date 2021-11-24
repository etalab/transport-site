defmodule TransportWeb.API.NotificationsControllerTest do
  use TransportWeb.ConnCase, async: true
  alias TransportWeb.API.Router.Helpers
  import Mox

  setup :verify_on_exit!

  test "post with authorization header", %{conn: conn} do
    conn |> post(Helpers.notifications_path(conn, :clear_config_cache)) |> json_response(401)
  end

  test "post with invalid authorization header", %{conn: conn} do
    conn
    |> put_req_header("authorization", "foobar")
    |> post(Helpers.notifications_path(conn, :clear_config_cache))
    |> json_response(401)
  end

  test "post with valid authorization header", %{conn: conn} do
    secret = "token #{Application.fetch_env!(:transport, :notifications_api_token)}"

    Transport.Notifications.FetcherMock
    |> expect(:clear_config_cache!, 1, fn -> nil end)

    conn
    |> put_req_header("authorization", secret)
    |> post(Helpers.notifications_path(conn, :clear_config_cache))
    |> json_response(200)
  end
end
