defmodule TransportWeb.ExploreControllerTest do
  use TransportWeb.ConnCase

  test "GET /explore/vehicle-positions", %{conn: conn} do
    conn = conn |> get("/explore/vehicle-positions")
    html = html_response(conn, 200)
    assert html =~ "Positions des véhicules"
  end
end
