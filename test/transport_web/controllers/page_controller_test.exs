defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get conn, "/"
    assert html_response(conn, 200) =~ "<main id=\"main\" role=\"main\">\n\n    </main>"
  end
end
