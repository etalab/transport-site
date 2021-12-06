defmodule TransportWeb.LiveDashboardTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  @endpoint TransportWeb.Endpoint

  @dashboard_url "/ops/dashboard/home"

  test "requires authentication" do
    conn =
      build_conn()
      |> get(@dashboard_url)

    assert response(conn, 401) =~ ~r/Unauthorized/
  end

  test "accepts authenticated request" do
    user = Application.fetch_env!(:transport, :ops_auth_username)
    pass = Application.fetch_env!(:transport, :ops_auth_password)
    auth = Plug.BasicAuth.encode_basic_auth(user, pass)

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", auth)
      |> get(@dashboard_url)

    assert response(conn, 200) =~ ~r/Phoenix LiveDashboard/
  end
end
