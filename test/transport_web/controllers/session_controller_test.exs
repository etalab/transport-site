defmodule TransportWeb.SessionControllerTest do
  use TransportWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  doctest TransportWeb.SessionController

  test "GET /login/callback", %{conn: conn} do
    use_cassette "session/create-2" do
      conn = conn |> get(session_path(conn, :create, %{"code" => "secret"}))
      assert redirected_to(conn, 302) == user_path(conn, :organizations)
    end
  end
end
