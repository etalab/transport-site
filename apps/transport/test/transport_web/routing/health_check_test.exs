defmodule TransportWeb.HealthCheckTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import Mock

  test "GET /health-check", %{conn: conn} do
    conn = get(conn, "/health-check")
    body = text_response(conn, 200)
    assert body |> String.split("\n") == ["db: OK", "http: OK"]
  end

  test "GET /health-check (with db not available)", %{conn: conn} do
    with_mock Ecto.Adapters.SQL, query!: fn _, _, _ -> raise DBConnection.ConnectionError end do
      conn = get(conn, "/health-check")
      body = text_response(conn, 500)
      assert body |> String.split("\n") == ["db: KO", "http: OK"]

      assert_called_exactly(Ecto.Adapters.SQL.query!(:_, :_, :_), 1)
    end
  end

  test "GET /health-check?db=0 (with db not available", %{conn: conn} do
    with_mock Ecto.Adapters.SQL, query!: fn _, _, _ -> raise DBConnection.ConnectionError end do
      conn = get(conn, "/health-check?db=0")
      body = text_response(conn, 200)
      assert body |> String.split("\n") == ["http: OK"]

      assert_called_exactly(Ecto.Adapters.SQL.query!(:_, :_, :_), 0)
    end
  end
end
