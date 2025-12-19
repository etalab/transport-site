defmodule TransportWeb.API.StatsControllerTest do
  use TransportWeb.DatabaseCase, async: false, cleanup: [:datasets, :dataset_triggers]
  use TransportWeb.ConnCase
  import Mock
  import DB.Factory

  @cached_features_routes [
    {"/api/stats", "api-stats-aoms"},
    {"/api/stats/quality", "api-stats-quality"}
  ]

  for {route, cache_key} <- @cached_features_routes do
    test "GET #{route} (invokes the cache system)", %{conn: conn} do
      # return original computed payload
      mock = fn unquote(cache_key), x, _ -> x.() end

      with_mock Transport.Cache, fetch: mock do
        conn = conn |> get(unquote(route))
        %{"features" => _features} = json_response(conn, 200)
        assert_called_exactly(Transport.Cache.fetch(:_, :_, :_), 1)
      end
    end

    test "GET #{route} (returns the cached value as is)", %{conn: conn} do
      mock = fn unquote(cache_key), _, _ -> %{hello: 123} |> Jason.encode!() end

      with_mock Transport.Cache, fetch: mock do
        conn = conn |> get(unquote(route))
        assert json_response(conn, 200) == %{"hello" => 123}
      end
    end
  end

  test "Get the vehicles sharing stats" do
    ad =
      insert(:administrative_division,
        type: :epci,
        insee: "01",
        geom:
          "SRID=4326;POLYGON((55.5832 -21.3723,55.5510 -21.3743,55.5359 -21.3631,55.5832 -21.3723))"
          |> Geo.WKT.decode!()
      )

    dataset1 =
      insert(:dataset, %{
        type: "vehicles-sharing",
        is_active: true,
        declarative_spatial_areas: [ad],
        custom_title: "other name",
        slug: "a"
      })

    dataset2 =
      insert(:dataset, %{
        type: "vehicles-sharing",
        is_active: true,
        declarative_spatial_areas: [ad],
        custom_title: "name",
        slug: "z"
      })

    insert(:dataset)

    expected = [
      %{
        "geometry" => %{
          "coordinates" => [[[55.5832, -21.3723], [55.551, -21.3743], [55.5359, -21.3631], [55.5832, -21.3723]]],
          "crs" => %{"properties" => %{"name" => "EPSG:4326"}, "type" => "name"},
          "type" => "Polygon"
        },
        "properties" => %{
          names: [dataset2.custom_title, dataset1.custom_title],
          slugs: [dataset2.slug, dataset1.slug]
        },
        "type" => "Feature"
      }
    ]

    assert TransportWeb.API.StatsController.vehicles_sharing_features_query()
           |> DB.Repo.all()
           |> TransportWeb.API.StatsController.vehicles_sharing_features() == expected

    # result can be encoded
    refute expected |> Jason.encode!() |> is_nil()
  end

  test "can load the /stats page", %{conn: conn} do
    insert(:resource_metadata, features: ["service_alerts"], resource: insert(:resource, format: "gtfs-rt"))

    insert(:resource_metadata,
      features: ["service_alerts", "vehicle_positions"],
      resource: insert(:resource, format: "gtfs-rt")
    )

    insert_bnlc_dataset()
    insert_parcs_relais_dataset()
    insert_irve_dataset()
    insert_zfe_dataset()

    conn2 = conn |> get(TransportWeb.Router.Helpers.stats_path(conn, :index))
    assert conn2 |> html_response(200)
  end
end
