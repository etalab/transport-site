defmodule TransportWeb.ProxyRoutingTest do
  use TransportWeb.ConnCase, async: true

  test "accepts proxy. subdomain, calls and delegates them to Unlock", %{conn: conn} do
    conn = %{conn | host: "proxy.example.com"} |> get(~p"/")

    [h] = Plug.Conn.get_resp_header(conn, "x-request-id")
    assert h

    assert text_response(conn, 200) =~ "Unlock"
  end

  test "rate limiter is not enabled for proxy", %{conn: conn} do
    [blocked_ip] = Application.fetch_env!(:phoenix_ddos, :blocklist_ips)

    response =
      %{conn | host: "proxy.example.com"}
      |> Plug.Conn.put_req_header("x-forwarded-for", to_string(blocked_ip))
      |> get(~p"/")
      |> text_response(200)

    assert response =~ "Unlock"
  end
end
