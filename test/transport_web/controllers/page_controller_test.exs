defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase, async: true

  doctest TransportWeb.PageController

  test "GET /", %{conn: conn} do
    conn = conn |> get(page_path(conn, :index))
    assert html_response(conn, 200) =~ "disponible, valoriser et améliorer"
  end

  test "GET /search_organizations", %{conn: conn} do
    conn = conn |> get(page_path(conn, :search_organizations))
    assert html_response(conn, 200) =~ "</organization-search>"
  end
end
