defmodule TransportWeb.HeadersAndCookiesTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets]

  test "sets expected headers", %{conn: conn} do
    conn = get(conn, "/")
    # Correct with security practises recommend in February 2022
    # https://github.com/phoenixframework/phoenix/pull/4677
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "x-download-options") == ["noopen"]
    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    assert get_resp_header(conn, "x-permitted-cross-domain-policies") == ["none"]

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

    datetime = TimeWrapper.parse!(datetime, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} GMT")
    assert_in_delta TimeWrapper.diff(datetime, TimeWrapper.now(), :hours), 15 * 24, 1
  end
end
