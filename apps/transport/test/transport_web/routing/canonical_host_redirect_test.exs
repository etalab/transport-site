defmodule TransportWeb.CanonicalRoutingTest do
  # we used shared sandbox
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  @endpoint TransportWeb.Endpoint

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "redirects browser calls to canonical browser for GET queries" do
    conn =
      build_conn()
      |> Map.put(:host, "www.another.domain.com")
      |> get(path = "/something?with=query&params=1")

    assert conn.status == 301
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com" <> path]
  end
end
