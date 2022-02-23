defmodule TransportWeb.HealthCheckControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import Mock

  test "GET /health-check", %{conn: conn} do
    conn = get(conn, "/health-check")
    body = json_response(conn, 200)
    assert body == %{"database" => "OK"}
  end

  test "GET /health-check (with db not available)", %{conn: conn} do
    with_mock Ecto.Adapters.SQL, query!: fn _, _, _ -> raise DBConnection.ConnectionError end do
      conn = get(conn, "/health-check")
      body = json_response(conn, 500)
      assert body == %{"database" => "KO"}
    end
  end
end
