defmodule TransportWeb.ProxyRoutingTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.ConnTest

  test "accepts proxy. subdomain calls and delegates them to unlock", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "proxy.example.com")
      |> get("/")

    [h] = Plug.Conn.get_resp_header(conn, "x-request-id")
    assert h

    assert text_response(conn, 200) =~ ~r/Unlock/
  end
end
