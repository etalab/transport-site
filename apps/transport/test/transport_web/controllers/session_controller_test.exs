defmodule TransportWeb.SessionControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase

  doctest TransportWeb.SessionController

  setup do
    Mox.stub_with(Datagouvfr.Authentication.Mock, Datagouvfr.Authentication.Dummy)
    Mox.stub_with(Datagouvfr.Client.User.Mock, Datagouvfr.Client.User.Dummy)
    :ok
  end

  test "GET /login/callback", %{conn: conn} do
    conn = conn |> get(session_path(conn, :create, %{"code" => "secret"}))
    current_user = get_session(conn, :current_user)

    assert redirected_to(conn, 302) == "/"
    assert Map.has_key?(current_user, "id") == true
    assert Map.has_key?(current_user, "avatar") == false
  end

  test "GET /login/callback and redirection to /datasets", %{conn: conn} do
    conn =
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))

    assert redirected_to(conn, 302) == "/datasets"
  end
end
