defmodule TransportWeb.UserControllerTest do
  use TransportWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  import Plug.Test

  doctest TransportWeb.UserController

  describe "GET /user/organizations" do
    test "logged in", %{conn: conn} do
      use_cassette "client/me-1" do
        conn = conn
        |> init_test_session(current_user: %{}, access_token: "secret")
        |> get(user_path(conn, :organizations))

        assert html_response(conn, 200)
      end
    end

    test "not logged in", %{conn: conn} do
      conn = conn |> get(user_path(conn, :organizations))
      assert redirected_to(conn, 302) == page_path(conn, :login)
    end
  end
end
