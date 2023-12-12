defmodule TransportWeb.Backoffice.RateLimiterLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import TransportWeb.ConnCase, only: [setup_admin_in_session: 1]

  @endpoint TransportWeb.Endpoint
  @url "/backoffice/rate_limiter"

  setup do
    {:ok, conn: build_conn()}
  end

  test "requires login", %{conn: conn} do
    conn
    |> get(@url)
    |> html_response(302)
  end

  test "page can load", %{conn: conn} do
    conn
    |> setup_admin_in_session()
    |> get(@url)
    |> html_response(200)
  end

  test "ips_in_jail" do
    assert [] == TransportWeb.Backoffice.RateLimiterLive.ips_in_jail()
    PhoenixDDoS.Jail.send(~c"108.128.238.17", {nil, %{jail_time: {1, :hour}}})
    assert ["108.128.238.17"] == TransportWeb.Backoffice.RateLimiterLive.ips_in_jail()
  end
end
