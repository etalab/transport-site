defmodule TransportWeb.OrganizationsControllerTest do
  use TransportWeb.ConnCase

  test "GET /organizations/_search", %{conn: conn} do
    conn = get conn, "/organizations/_search"
    assert html_response(conn, 200) =~ "<organization-search></organization-search>"
  end
end
