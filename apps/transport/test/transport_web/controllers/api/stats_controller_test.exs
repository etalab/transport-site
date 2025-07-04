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

  test "Get the vehicles sharing stats", %{conn: _conn} do
    aom =
      insert(:aom,
        geom:
          "SRID=4326;POLYGON((55.5832 -21.3723,55.5510 -21.3743,55.5359 -21.3631,55.5832 -21.3723))"
          |> Geo.WKT.decode!()
      )

    dataset1 =
      :dataset
      |> insert(%{type: "vehicles-sharing", is_active: true, aom: aom, custom_title: "other name", slug: "a"})

    dataset2 =
      :dataset |> insert(%{type: "vehicles-sharing", is_active: true, aom: aom, custom_title: "name", slug: "z"})

    expected = [
      %{
        "geometry" => %{
          "coordinates" => [55.5567, -21.3699],
          "crs" => %{"properties" => %{"name" => "EPSG:4326"}, "type" => "name"},
          "type" => "Point"
        },
        "properties" => %{
          geometry: %Geo.Point{coordinates: {55.5567, -21.3699}, properties: %{}, srid: 4326},
          names: [dataset2.custom_title, dataset1.custom_title],
          slugs: [dataset2.slug, dataset1.slug]
        },
        "type" => "Feature"
      }
    ]

    assert TransportWeb.API.StatsController.vehicles_sharing_features_query()
           |> DB.Repo.all()
           |> TransportWeb.API.StatsController.vehicles_sharing_features() == expected
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

  describe("aom quality features") do
    test "count vehicles sharing" do
      aom1 = insert(:aom, nom: "aom")
      insert(:dataset, is_active: true, type: "vehicles-sharing", aom: aom1)
      insert(:dataset, is_active: false, type: "vehicles-sharing", aom: aom1)

      assert %{dataset_types: %{vehicles_sharing: 1, pt: 0}} =
               TransportWeb.API.StatsController.quality_features_query() |> DB.Repo.get(aom1.id)
    end

    test "count public-transit" do
      aom1 = insert(:aom, nom: "aom")
      insert(:dataset, is_active: true, type: "public-transit", aom: aom1)
      insert(:dataset, is_active: false, type: "public-transit", aom: aom1)

      assert %{dataset_types: %{pt: 1}} =
               TransportWeb.API.StatsController.quality_features_query() |> DB.Repo.get(aom1.id)
    end

    test "expired from" do
      aom1 = insert(:aom, nom: "aom")

      insert_resource_and_friends(Date.utc_today() |> Date.add(-10), aom: aom1)
      insert_resource_and_friends(Date.utc_today() |> Date.add(-5), aom: aom1)
      # inactive
      insert_resource_and_friends(Date.utc_today() |> Date.add(-2), aom: aom1, is_active: false)
      # other aom
      insert_resource_and_friends(Date.utc_today() |> Date.add(-2), [])

      assert %{quality: %{expired_from: 5}} =
               TransportWeb.API.StatsController.quality_features_query() |> DB.Repo.get(aom1.id)
    end

    test "error level" do
      aom1 = insert(:aom, nom: "aom")

      # one dataset with "Error" level
      insert_resource_and_friends(Date.utc_today() |> Date.add(10), aom: aom1, max_error: "Error")

      # one dataset with "Information" and "Warning" level
      %{dataset: dataset} =
        insert_resource_and_friends(Date.utc_today() |> Date.add(10), aom: aom1, max_error: "Information")

      insert_resource_and_friends(Date.utc_today() |> Date.add(10), dataset: dataset, max_error: "Warning")

      # NoError but outdated
      insert_resource_and_friends(Date.utc_today() |> Date.add(-10), aom: aom1, max_error: "NoError")
      # NoError but other aom
      insert_resource_and_friends(Date.utc_today() |> Date.add(10), max_error: "NoError")
      # NoError but inactive dataset
      insert_resource_and_friends(Date.utc_today() |> Date.add(10), max_error: "NoError", is_active: false)

      assert %{quality: %{error_level: "Information"}} =
               TransportWeb.API.StatsController.quality_features_query() |> DB.Repo.get(aom1.id)
    end

    test "AOMs created in 2022 without datasets are not included" do
      aom =
        insert(:aom,
          nom: aom_nom = "aom",
          composition_res_id: 1_200,
          geom: "SRID=4326;LINESTRING(1 1,2 2)" |> Geo.WKT.decode!()
        )

      assert DB.AOM.created_after_2021?(aom)

      assert [] ==
               TransportWeb.API.StatsController.quality_features_query()
               |> DB.Repo.all()
               |> TransportWeb.API.StatsController.features()

      # If created before 2022, it is present even without a dataset
      aom = aom |> Ecto.Changeset.change(%{composition_res_id: 500}) |> DB.Repo.update!()

      refute DB.AOM.created_after_2021?(aom)

      assert [%{"properties" => %{"dataset_count" => 0, "nom" => ^aom_nom}}] =
               TransportWeb.API.StatsController.quality_features_query()
               |> DB.Repo.all()
               |> TransportWeb.API.StatsController.features()

      # Created in 2022 but with a dataset
      aom = aom |> Ecto.Changeset.change(%{composition_res_id: 1_200}) |> DB.Repo.update!()
      insert(:dataset, is_active: true, aom: aom, type: "public-transit")

      assert DB.AOM.created_after_2021?(aom)

      assert [%{"properties" => %{"dataset_types" => %{pt: 1}, "nom" => ^aom_nom}}] =
               TransportWeb.API.StatsController.quality_features_query()
               |> DB.Repo.all()
               |> TransportWeb.API.StatsController.features()
    end
  end

  test "uses legal owners to include datasets in AOMs" do
    aom =
      insert(:aom,
        nom: aom_nom = "aom",
        geom: "SRID=4326;LINESTRING(1 1,2 2)" |> Geo.WKT.decode!()
      )

    insert(:dataset, type: "public-transit", is_active: true, legal_owners_aom: [aom])
    insert(:dataset, type: "public-transit", is_active: true, legal_owners_aom: [aom])

    insert_resource_and_friends(Date.utc_today() |> Date.add(10),
      aom: aom,
      max_error: "Error",
      type: "road-data"
    )

    assert [
             %{
               "properties" => %{
                 "dataset_types" => %{pt: 2},
                 "nom" => ^aom_nom,
                 "quality" => %{"error_level" => "Error"}
               }
             }
           ] =
             TransportWeb.API.StatsController.quality_features_query()
             |> DB.Repo.all()
             |> TransportWeb.API.StatsController.features()
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
