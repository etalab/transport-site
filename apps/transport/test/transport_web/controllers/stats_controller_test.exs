defmodule TransportWeb.API.StatsControllerTest do
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase
  import Mock

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
        %{"features" => features} = json_response(conn, 200)
        # NOTE: we'll need to add real data instead, this just tests the caching path
        assert features == []
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
end
