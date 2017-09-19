defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get conn, "/"
    assert html_response(conn, 200) =~ "Rendre disponible, valoriser et améliorer les données transports"
  end
end
