defmodule TransportWeb.CanonicalRoutingTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.ConnTest

  test "redirects browser calls to canonical browser for GET queries", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "www.another.domain.com")
      |> get(path = "/something?with=query&params=1")

    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com" <> path]
  end
end
