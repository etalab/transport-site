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
    insert(:dataset, is_active: false, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience", "foo"], type: "road-data")

    assert %{
             climate_resilience_bill_count: %{
               "road-data" => 1,
               "public-transit" => 2
             }
           } = compute_stats()
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

    # climate_resilience_bill data
    insert(:dataset, is_active: false, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience"], type: "public-transit")
    insert(:dataset, is_active: true, custom_tags: ["loi-climat-resilience", "foo"], type: "road-data")

    # reuses stats
    insert(:reuse, type: "api", metric_discussions: 0, metric_followers: 2, metric_views: 5)
    insert(:reuse, type: "visualization", metric_discussions: 1, metric_followers: 1, metric_views: 10)

    stats = compute_stats()
    store_stats()
    assert DB.Repo.aggregate(DB.StatsHistory, :count, :id) >= Enum.count(stats)

    all_metrics = DB.StatsHistory |> select([s], s.metric) |> DB.Repo.all()

    stats_metrics =
      stats
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(
        &String.starts_with?(&1, ["gtfs_rt_types", "climate_resilience_bill_count", "count_geo_data_lines", "reuses"])
      )

    assert MapSet.subset?(MapSet.new(stats_metrics), MapSet.new(all_metrics))
    assert Enum.member?(all_metrics, "gtfs_rt_types::vehicle_positions")
    assert Enum.member?(all_metrics, "gtfs_rt_types::trip_updates")
    assert Enum.member?(all_metrics, "count_geo_data_lines::irve")
    assert Enum.member?(all_metrics, "reuses::nb_reuses")

    expected = Decimal.new(2)
    assert %{value: ^expected} = DB.Repo.get_by!(DB.StatsHistory, metric: "gtfs_rt_types::vehicle_positions")
    expected = Decimal.new(1)
    assert %{value: ^expected} = DB.Repo.get_by!(DB.StatsHistory, metric: "gbfs_v3.0_count")
    expected = Decimal.new(15)
    assert %{value: ^expected} = DB.Repo.get_by!(DB.StatsHistory, metric: "reuses::sum_metric_views")

    decimal_1 = Decimal.new(1)
    decimal_2 = Decimal.new(2)

    assert [
             %DB.StatsHistory{metric: "climate_resilience_bill_count::public-transit", value: ^decimal_2},
             %DB.StatsHistory{metric: "climate_resilience_bill_count::road-data", value: ^decimal_1}
           ] =
             DB.StatsHistory
             |> where([s], like(s.metric, "climate_resilience_bill_count%"))
             |> order_by([s], s.metric)
             |> DB.Repo.all()
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
    aom = insert(:aom)
    dataset = insert(:dataset, legal_owners_aom: [aom])
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Error")
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Warning")
    insert_outdated_resource_and_friends(dataset: dataset, max_error: "Fatal")

    assert %{"Error" => 1} == compute_aom_gtfs_max_severity()
  end

  test "compute aom max severity bis" do
    aom_1 = insert(:aom)
    dataset = insert(:dataset, legal_owners_aom: [aom_1])
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Fatal")

    aom_2 = insert(:aom)
    dataset = insert(:dataset, legal_owners_aom: [aom_2])
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Fatal")

    aom_3 = insert(:aom)
    dataset = insert(:dataset, legal_owners_aom: [aom_3])
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Warning")

    aom_4 = insert(:aom)
    dataset = insert(:dataset, legal_owners_aom: [aom_4])
    insert_up_to_date_resource_and_friends(dataset: dataset, max_error: "Information")
    insert_outdated_resource_and_friends(dataset: dataset, max_error: "Fatal")

    assert %{"Fatal" => 2, "Warning" => 1, "Information" => 1} == compute_aom_gtfs_max_severity()
  end

  test "uses legal owners to assign datasets to AOMs" do
    DB.Dataset |> DB.Repo.delete_all()
    DB.AOM |> DB.Repo.delete_all()

    insert(:aom, population: 1_000_000)
    aom2 = insert(:aom, population: 1_000_000)
    insert(:aom, population: 1_000_000)

    insert(:dataset, legal_owners_aom: [aom2], aom: nil)

    assert %{nb_aoms_with_data: 1, nb_aoms: 3, population_couverte: 1, population_totale: 3} = compute_stats()
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

  test "reuses_stats" do
    insert(:reuse, type: "api", metric_discussions: 0, metric_followers: 2, metric_views: 5)
    insert(:reuse, type: "visualization", metric_discussions: 1, metric_followers: 1, metric_views: 10)

    assert %{
             :nb_reuses => 2,
             :sum_metric_discussions => 1,
             :sum_metric_followers => 3,
             :sum_metric_views => 15,
             "api" => 1,
             "visualization" => 1
           } = reuses_stats = reuses_stats()

    assert %{reuses: ^reuses_stats} = compute_stats()
  end
end
