defmodule TransportWeb.API.StatsControllerTest do
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase, async: false
  import Mock

  @tag :focus
  test "GET /api/stats/regions (invokes the cache system)", %{conn: conn} do
    # return original computed payload
    mock = fn _, x -> x.() end

    with_mock Transport.Cache.API, fetch: mock do
      conn = conn |> get("/api/stats/regions")
      %{"features" => features} = json_response(conn, 200)
      # NOTE: we'll need to add real data instead, this just tests the caching path
      assert features == []
      assert_called_exactly(Transport.Cache.API.fetch(:_, :_), 1)
    end
  end

  @tag :focus
  test "GET /api/stats/regions (returns the cached value as is)", %{conn: conn} do
    mock = fn _, _ -> %{hello: 123} |> Jason.encode!() end

    with_mock Transport.Cache.API, fetch: mock do
      conn = conn |> get("/api/stats/regions")
      assert json_response(conn, 200) == %{"hello" => 123}
    end
  end
end
