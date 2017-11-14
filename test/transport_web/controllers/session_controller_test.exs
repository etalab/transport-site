defmodule TransportWeb.SessionControllerTest do
  use TransportWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  import Plug.Test

  doctest TransportWeb.SessionController

  test "GET /login/callback", %{conn: conn} do
    use_cassette "session/create-2" do
      conn = conn |> get(session_path(conn, :create, %{"code" => "secret"}))
      current_user = get_session(conn, :current_user)

      assert redirected_to(conn, 302) == "/"
      assert Map.has_key?(current_user, "id") == true
      assert Map.has_key?(current_user, "avatar") == false
    end
  end

  test "GET /login/callback and redirection to /datasets", %{conn: conn} do
    use_cassette "session/create-2" do
      conn =
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))

      assert redirected_to(conn, 302) == "/datasets"
    end
  end
end
