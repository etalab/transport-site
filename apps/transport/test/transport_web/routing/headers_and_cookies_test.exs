defmodule TransportWeb.HeadersAndCookiesTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets]

  test "sets expected headers", %{conn: conn} do
    conn = get(conn, "/")
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "x-xss-protection") == ["1; mode=block"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    [header] = get_resp_header(conn, "set-cookie")
    %{
      "_transport_key" => _some_value,
      "path" => "/",
      "SameSite" => "Lax"
    } = Plug.Conn.Cookies.decode(header)
  end
end
