defmodule TransportWeb.HeadersAndCookiesTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]

  test "sets expected headers", %{conn: conn} do
    conn = get(conn, "/")
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(conn, "x-xss-protection") == ["1; mode=block"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    [header] = get_resp_header(conn, "set-cookie")
    # 15 days, in seconds
    max_age = (24 * 60 * 60 * 15) |> Integer.to_string()

    %{
      "_transport_key" => _some_value,
      "path" => "/",
      "SameSite" => "Lax",
      "max-age" => ^max_age,
      "expires" => datetime
    } = Plug.Conn.Cookies.decode(header)

    datetime = Timex.parse!(datetime, "{WDshort}, {D} {Mfull} {YYYY} {h24}:{m}:{s} GMT")
    assert_in_delta Timex.diff(datetime, Timex.now(), :days), 14, 1
  end
end
