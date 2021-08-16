defmodule TransportWeb.API.StatsControllerTest do
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase
  import Mock
  import TransportWeb.Factory

  @cached_features_routes [
    {"/api/stats", "api-stats-aoms"},
    {"/api/stats/regions", "api-stats-regions"},
    {"/api/stats/quality", "api-stats-quality"}
  ]

  for {route, cache_key} <- @cached_features_routes do
    test "GET #{route} (invokes the cache system)", %{conn: conn} do
      # return original computed payload
      mock = fn unquote(cache_key), x -> x.() end

      with_mock Transport.Cache.API, fetch: mock do
        conn = conn |> get(unquote(route))
        %{"features" => _features} = json_response(conn, 200)
        assert_called_exactly(Transport.Cache.API.fetch(:_, :_), 1)
      end
    end

    test "GET #{route} (returns the cached value as is)", %{conn: conn} do
      mock = fn unquote(cache_key), _ -> %{hello: 123} |> Jason.encode!() end

      with_mock Transport.Cache.API, fetch: mock do
        conn = conn |> get(unquote(route))
        assert json_response(conn, 200) == %{"hello" => 123}
      end
    end
  end

  test "Get the bike and scooter stats", %{conn: _conn} do
    _dataset = :dataset |> insert(%{type: "bike-scooter-sharing"})
    result = TransportWeb.API.StatsController.bike_scooter_sharing_features_query() |> DB.Repo.all()
    assert length(result) == 1
  end
end
