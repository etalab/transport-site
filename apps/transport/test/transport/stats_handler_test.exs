defmodule Transport.StatsHandlerTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  import Transport.StatsHandler

  doctest Transport.StatsHandler, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    insert_bnlc_dataset()
    insert_irve_dataset()
    insert_parcs_relais_dataset()
    insert_zfe_dataset()
    :ok
  end

  test "compute_stats" do
    assert is_map(compute_stats())
  end

  test "count_feed_types_gtfs_rt" do
    resource = insert(:resource, format: "gtfs-rt")
    # should not be used as this is too old
    insert(:resource_metadata,
      features: ["foo"],
      resource_id: resource.id,
      inserted_at: Transport.Jobs.GTFSRTMetadataJob.datetime_limit() |> DateTime.add(-5)
    )

    # Empty cases, should not crash
    insert(:resource_metadata, features: [], resource_id: resource.id)
    insert(:resource_metadata, features: nil, resource_id: resource.id)

    # recent metadata for the resource
    insert(:resource_metadata, features: ["vehicle_positions", "entity"], resource_id: resource.id)
    insert(:resource_metadata, features: ["vehicle_positions", "trip_updates"], resource_id: resource.id)

    # another resource linked to a single metadata
    insert(:resource_metadata,
      features: ["vehicle_positions", "service_alerts"],
      resource: insert(:resource, format: "gtfs-rt")
    )

    assert %{"service_alerts" => 1, "trip_updates" => 1, "vehicle_positions" => 2, "entity" => 1} ==
             count_feed_types_gtfs_rt()
  end

  test "climate_resilience_bill_count" do
    aom = insert(:aom, population: 1_000)
    insert(:dataset, aom: aom, is_active: false, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, aom: aom, is_active: true, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, aom: aom, is_active: true, custom_tags: ["loi-climat-resilience"], type: "public-transit")

    insert(:dataset,
      aom: aom,
      is_active: true,
      custom_tags: ["loi-climat-resilience", "foo"],
      type: "low-emission-zones"
    )

    assert %{
             climate_resilience_bill_count: %{
               "low-emission-zones" => 1,
               "public-transit" => 2
             }
           } = compute_stats()

    # Stored as expected in the database
    store_stats()

    decimal_1 = Decimal.new(1)
    decimal_2 = Decimal.new(2)

    assert [
             %DB.StatsHistory{metric: "climate_resilience_bill_count::low-emission-zones", value: ^decimal_1},
             %DB.StatsHistory{metric: "climate_resilience_bill_count::public-transit", value: ^decimal_2}
           ] =
             DB.StatsHistory
             |> where([s], like(s.metric, "climate_resilience_bill_count%"))
             |> order_by([s], s.metric)
             |> DB.Repo.all()
  end

  test "store_stats" do
    gtfs_rt_resource = insert(:resource, format: "gtfs-rt")
    insert(:resource_metadata, features: ["vehicle_positions"], resource_id: gtfs_rt_resource.id)
    insert(:resource_metadata, features: ["trip_updates"], resource_id: gtfs_rt_resource.id)
    insert(:resource_metadata, features: ["vehicle_positions"], resource: insert(:resource, format: "gtfs-rt"))

    insert(:resource_metadata,
      metadata: %{
        versions: ["3.0"],
        types: ["free_floating"],
        vehicle_types: ["scooter"],
        stats: %{nb_vehicles: 10, version: 1}
      },
      resource_id: insert(:resource, format: "gbfs").id
    )

    stats = compute_stats()
    store_stats()
    assert DB.Repo.aggregate(DB.StatsHistory, :count, :id) >= Enum.count(stats)

    all_metrics = DB.StatsHistory |> select([s], s.metric) |> DB.Repo.all()

    stats_metrics =
      stats
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(
        &String.starts_with?(&1, ["gtfs_rt_types", "climate_resilience_bill_count", "count_geo_data_lines"])
      )

    assert MapSet.subset?(MapSet.new(stats_metrics), MapSet.new(all_metrics))
    assert Enum.member?(all_metrics, "gtfs_rt_types::vehicle_positions")
    assert Enum.member?(all_metrics, "gtfs_rt_types::trip_updates")
    assert Enum.member?(all_metrics, "count_geo_data_lines::irve")

    expected = Decimal.new("2")
    assert %{value: ^expected} = DB.Repo.get_by!(DB.StatsHistory, metric: "gtfs_rt_types::vehicle_positions")
    expected = Decimal.new("1")
    assert %{value: ^expected} = DB.Repo.get_by!(DB.StatsHistory, metric: "gbfs_v3.0_count")
  end

  test "count dataset per format" do
    inactive_dataset = insert(:dataset, is_active: false)
    insert(:resource, dataset_id: inactive_dataset.id, format: format = "xxx")

    active_dataset = insert(:dataset, is_active: true)
    insert(:resource, dataset_id: active_dataset.id, format: format)

    count_resources = count_dataset_with_format(format)

    assert count_resources == 1
  end

  test "compute aom max severity" do
    aom_1 = insert(:aom)
    %{dataset: dataset} = insert_up_to_date_resource_and_friends(max_error: "Error", aom: aom_1)
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Warning")
    insert_outdated_resource_and_friends(dataset: dataset, max_error: "Fatal")

    aoms = compute_aom_gtfs_max_severity()

    assert %{"Error" => 1} == aoms
  end

  test "compute aom max severity bis" do
    aom_1 = insert(:aom)
    insert_up_to_date_resource_and_friends(max_error: "Fatal", aom: aom_1)

    aom_2 = insert(:aom)
    insert_up_to_date_resource_and_friends(max_error: "Fatal", aom: aom_2)

    aom_3 = insert(:aom)
    insert_up_to_date_resource_and_friends(max_error: "Warning", aom: aom_3)

    aom_4 = insert(:aom)
    %{dataset: dataset} = insert_up_to_date_resource_and_friends(max_error: "Information", aom: aom_4)
    insert_outdated_resource_and_friends(dataset: dataset, max_error: "Fatal")

    aoms = compute_aom_gtfs_max_severity()

    assert %{"Fatal" => 2, "Warning" => 1, "Information" => 1} == aoms
  end

  test "uses legal owners to assign datasets to AOMs" do
    # There are existing datasets and AOMs in the database since we inserted some datasets in the setup method
    aom1 = insert(:aom, population: 1_000_000)
    aom2 = insert(:aom, population: 1_000_000)
    insert(:aom, population: 1_000_000)
    insert(:dataset, type: "public-transit", is_active: true, legal_owners_aom: [aom2], aom: aom1)

    assert %{nb_aoms_with_data: 6, nb_aoms: 7, population_couverte: 6, population_totale: 7} = compute_stats()
  end

  test "ignores hidden datasets" do
    aom = insert(:aom, population: 1_000_000)
    insert(:resource, dataset: insert(:dataset, aom: aom, is_active: true), format: "GTFS")

    hidden_dataset = insert(:dataset, aom: aom, is_active: true, is_hidden: true)
    insert(:resource, dataset: hidden_dataset, format: "GTFS")

    assert %{nb_datasets: 5, nb_gtfs: 1, nb_pt_datasets: 1} = compute_stats()
  end

  test "counts the number of IRVE lines in GeoData" do
    assert 0 == count_geo_data_lines(:irve)
    insert_imported_irve_geo_data(Transport.ConsolidatedDataset.dataset(:irve).id)
    assert 2 == count_geo_data_lines(:irve)
  end

  describe "gbfs_stats" do
    test "no rows for today" do
      insert(:resource_metadata,
        metadata: %{"stats" => 42},
        resource_id: insert(:resource, format: "gbfs").id,
        inserted_at: DateTime.add(DateTime.utc_now(), -1, :day)
      )

      assert %{} == gbfs_stats()
    end

    test "it works" do
      gbfs_resource = insert(:resource, format: "gbfs")
      other_gbfs_resource = insert(:resource, format: "gbfs")
      gtfs_resource = insert(:resource, format: "GTFS")

      now = DateTime.utc_now()

      # Should be ignored: GTFS
      insert(:resource_metadata, metadata: %{foo: 42}, resource_id: gtfs_resource.id)
      # Should be ignored: not the most recent one for `gbfs_resource`
      insert(:resource_metadata,
        metadata: %{stats: %{foo: 42}},
        resource_id: gbfs_resource.id,
        inserted_at: DateTime.add(now, -5, :second)
      )

      # Relevant metadata
      insert(:resource_metadata,
        metadata: %{
          versions: ["3.0", "2.3"],
          types: ["stations"],
          vehicle_types: ["bicycle", "scooter"],
          stats: %{nb_vehicles: 20, nb_stations: 3, version: 1}
        },
        resource_id: gbfs_resource.id
      )

      insert(:resource_metadata,
        metadata: %{
          versions: ["3.0"],
          types: ["free_floating"],
          vehicle_types: ["scooter"],
          stats: %{nb_vehicles: 10, version: 1}
        },
        resource_id: other_gbfs_resource.id
      )

      assert %{
               gbfs_feed_type_free_floating_count: 1,
               gbfs_feed_type_stations_count: 1,
               gbfs_nb_stations_sum: 3,
               gbfs_nb_vehicles_sum: 30,
               "gbfs_v2.3_count": 1,
               "gbfs_v3.0_count": 2,
               gbfs_vehicle_type_bicycle_count: 1,
               gbfs_vehicle_type_scooter_count: 2
             } == gbfs_stats()
    end
  end

  test "Get the bike and scooter stats" do
    aom =
      insert(:aom,
        geom:
          "SRID=4326;POLYGON((55.5832 -21.3723,55.5510 -21.3743,55.5359 -21.3631,55.5832 -21.3723))"
          |> Geo.WKT.decode!()
      )

    dataset1 =
      :dataset
      |> insert(%{type: "bike-scooter-sharing", is_active: true, aom: aom, custom_title: "other name", slug: "a"})

    dataset2 =
      :dataset |> insert(%{type: "bike-scooter-sharing", is_active: true, aom: aom, custom_title: "name", slug: "z"})

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

    assert Transport.StatsHandler.bike_scooter_sharing_features(Transport.StatsHandler.bike_scooter_features_query()) ==
             expected
  end

  describe("aom quality features") do
    test "count scooter and bikes" do
      aom1 = insert(:aom, nom: "aom")
      insert(:dataset, is_active: true, type: "bike-scooter-sharing", aom: aom1)
      insert(:dataset, is_active: false, type: "bike-scooter-sharing", aom: aom1)

      assert %{dataset_types: %{bike_scooter_sharing: 1, pt: 0}} =
               Transport.StatsHandler.quality_features_query() |> DB.Repo.get(aom1.id)
    end

    test "count public-transit" do
      aom1 = insert(:aom, nom: "aom")
      insert(:dataset, is_active: true, type: "public-transit", aom: aom1)
      insert(:dataset, is_active: false, type: "public-transit", aom: aom1)

      assert %{dataset_types: %{pt: 1}} =
               Transport.StatsHandler.quality_features_query() |> DB.Repo.get(aom1.id)
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
               Transport.StatsHandler.quality_features_query() |> DB.Repo.get(aom1.id)
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
               Transport.StatsHandler.quality_features_query() |> DB.Repo.get(aom1.id)
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
               Transport.StatsHandler.quality_features_query() |> Transport.StatsHandler.features()

      # If created before 2022, it is present even without a dataset
      aom = aom |> Ecto.Changeset.change(%{composition_res_id: 500}) |> DB.Repo.update!()

      refute DB.AOM.created_after_2021?(aom)

      assert [%{"properties" => %{"dataset_count" => 0, "nom" => ^aom_nom}}] =
               Transport.StatsHandler.quality_features_query() |> Transport.StatsHandler.features()

      # Created in 2022 but with a dataset
      aom = aom |> Ecto.Changeset.change(%{composition_res_id: 1_200}) |> DB.Repo.update!()
      insert(:dataset, is_active: true, aom: aom, type: "public-transit")

      assert DB.AOM.created_after_2021?(aom)

      assert [%{"properties" => %{"dataset_types" => %{pt: 1}, "nom" => ^aom_nom}}] =
               Transport.StatsHandler.quality_features_query() |> Transport.StatsHandler.features()
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
      type: "low-emission-zones"
    )

    assert [
             %{
               "properties" => %{
                 "dataset_types" => %{pt: 2},
                 "nom" => ^aom_nom,
                 "quality" => %{"error_level" => "Error"}
               }
             }
           ] = Transport.StatsHandler.quality_features_query() |> Transport.StatsHandler.features()
  end
end
