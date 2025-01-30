defmodule TransportWeb.API.StatsControllerTest do
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase
  import Mock
  import DB.Factory
  import OpenApiSpex.TestAssertions

  @cached_features_routes [
    {"/api/stats", "api-stats-aoms"},
    {"/api/stats/regions", "api-stats-regions"},
    {"/api/stats/quality", "api-stats-quality"}
  ]

  for {route, cache_key} <- @cached_features_routes do
    test "GET #{route} (invokes the cache system)", %{conn: conn} do
      # return original computed payload
      mock = fn unquote(cache_key), x -> x.() end

      with_mock Transport.Cache, fetch: mock do
        conn = conn |> get(unquote(route))
        %{"features" => _features} = json_response(conn, 200)
        assert_called_exactly(Transport.Cache.fetch(:_, :_), 1)
      end
    end

    test "GET #{route} (returns the cached value as is)", %{conn: conn} do
      mock = fn unquote(cache_key), _ -> %{hello: 123} |> Jason.encode!() end

      with_mock Transport.Cache, fetch: mock do
        conn = conn |> get(unquote(route))
        assert json_response(conn, 200) == %{"hello" => 123}
      end
    end
  end

  test "Quality of AOM data stats", %{conn: conn} do
    aom =
      insert(
        :aom,
        geom:
          "SRID=4326;POLYGON((55.5832 -21.3723,55.5510 -21.3743,55.5359 -21.3631,55.5832 -21.3723))"
          |> Geo.WKT.decode!()
      )

    %{id: dataset_active_id} =
      :dataset |> insert(%{type: "public-transit", is_active: true, aom: aom, custom_title: "Ajaccio", slug: "a"})

    # the active dataset has an outdated resource
    resource = :resource |> insert(dataset_id: dataset_active_id, is_available: true)
    resource_history = insert(:resource_history, resource_id: resource.id)

    validation =
      insert(:multi_validation,
        resource_history_id: resource_history.id,
        validator: Transport.Validators.GTFSTransport.validator_name()
      )

    insert(:resource_metadata, multi_validation_id: validation.id, metadata: %{"end_date" => Date.new!(2000, 1, 1)})

    %{id: dataset_inactive_id} =
      :dataset |> insert(%{type: "public-transit", is_active: false, aom: aom, custom_title: "Ajacciold", slug: "z"})

    # but the inactive dataset has an up-to-date resource
    resource_2 = :resource |> insert(dataset_id: dataset_inactive_id, is_available: true)
    resource_history_2 = insert(:resource_history, resource_id: resource_2.id)

    validation_2 =
      insert(:multi_validation,
        resource_history_id: resource_history_2.id,
        validator: Transport.Validators.GTFSTransport.validator_name()
      )

    insert(:resource_metadata, multi_validation_id: validation_2.id, metadata: %{"end_date" => Date.new!(2100, 1, 1)})

    res = conn |> get(TransportWeb.API.Router.Helpers.stats_path(conn, :quality)) |> json_response(200)

    # the aom status is outdated
    assert %{"features" => [%{"properties" => %{"quality" => %{"expired_from" => %{"status" => "outdated"}}}}]} = res

    assert_schema(res, "FeatureCollection", TransportWeb.API.Spec.spec())
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
    assert conn2 |> html_response(200) =~ ~s(<span title="service_alerts">Info trafic</span> : 2)
  end
end
