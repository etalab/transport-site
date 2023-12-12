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
end
