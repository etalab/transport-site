defmodule TransportWeb.ExploreControllerTest do
  use TransportWeb.ConnCase

  test "GET /explore", %{conn: conn} do
    conn = conn |> get("/explore")
    html = html_response(conn, 200)
    assert html =~ "Exploration"
  end

  test "GET /explore/vehicle-positions", %{conn: conn} do
    conn =
      conn
      |> get("/explore/vehicle-positions")

    assert redirected_to(conn, 302) == "/explore"
  end
end
