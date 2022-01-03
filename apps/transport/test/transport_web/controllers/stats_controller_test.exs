defmodule TransportWeb.API.StatsControllerTest do
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase
  import Mock
  import DB.Factory

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
    aom =
      insert(:aom,
        geom:
          "SRID=4326;POLYGON((55.5832 -21.3723,55.5510 -21.3743,55.5359 -21.3631,55.5832 -21.3723))"
          |> Geo.WKT.decode!()
      )

    dataset1 =
      :dataset |> insert(%{type: "bike-scooter-sharing", is_active: true, aom: aom, spatial: "other name", slug: "a"})

    dataset2 =
      :dataset |> insert(%{type: "bike-scooter-sharing", is_active: true, aom: aom, spatial: "name", slug: "z"})

    expected = [
      %{
        "geometry" => %{
          "coordinates" => [55.5567, -21.3699],
          "crs" => %{"properties" => %{"name" => "EPSG:4326"}, "type" => "name"},
          "type" => "Point"
        },
        "properties" => %{
          geometry: %Geo.Point{coordinates: {55.5567, -21.3699}, properties: %{}, srid: 4326},
          names: [dataset2.spatial, dataset1.spatial],
          slugs: [dataset2.slug, dataset1.slug]
        },
        "type" => "Feature"
      }
    ]

    assert TransportWeb.API.StatsController.bike_scooter_sharing_features() == expected
  end

  test "Quality of AOM data stats", %{conn: conn} do
    aom =
      insert(
        :aom,
        geom:
          "SRID=4326;POLYGON((55.5832 -21.3723,55.5510 -21.3743,55.5359 -21.3631,55.5832 -21.3723))"
          |> Geo.WKT.decode!()
      )

    dataset_active =
      %{id: dataset_active_id} =
      :dataset |> insert(%{type: "public-transit", is_active: true, aom: aom, spatial: "Ajaccio", slug: "a"})

    # the active dataset has an outdated resource
    outdated_resource = :resource |> insert(%{dataset_id: dataset_active_id, end_date: Date.new!(2000, 1, 1)})

    dataset_inactive =
      %{id: dataset_inactive_id} =
      :dataset |> insert(%{type: "public-transit", is_active: false, aom: aom, spatial: "Ajacciold", slug: "z"})

    # but the inactive dataset has an up-to-date resource
    up_to_date_resource = :resource |> insert(%{dataset_id: dataset_inactive_id, end_date: Date.new!(2100, 1, 1)})

    res = conn |> get(TransportWeb.API.Router.Helpers.stats_path(conn, :quality)) |> json_response(200)

    # the aom status is outdated
    assert %{"features" => [%{"properties" => %{"quality" => %{"expired_from" => %{"status" => "outdated"}}}}]} = res
  end
end
