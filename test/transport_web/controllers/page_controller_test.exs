defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get conn, "/"
    assert html_response(conn, 200) =~ "Rendre disponible, valoriser et améliorer les données transports"
  end

  test "GET /search_organizations", %{conn: conn} do
    conn = get conn, "/search_organizations"
    assert html_response(conn, 200) =~ "<organization-search></organization-search>"
  end

  test "GET /shortlist", %{conn: conn} do
    conn = get conn, "/shortlist"
    assert html_response(conn, 200) =~ "</shortlist>"
  end
end
