defmodule TransportWeb.ProxyRoutingTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  @endpoint TransportWeb.Endpoint

  test "accepts proxy. subdomain calls and delegates them to unlock" do
    conn = build_conn()
    |> Map.put(:host, "proxy.example.com")
    |> get("/")

    [h] = Plug.Conn.get_resp_header(conn, "x-request-id")
    assert h

    assert text_response(conn, 200) =~ ~r/Unlock/
  end
end
