defmodule Transport.StatsHandlerTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  import Transport.StatsHandler

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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
      inserted_at: Transport.Jobs.GTFSRTEntitiesJob.datetime_limit() |> DateTime.add(-5)
    )

    # Empty cases, should not crash
    insert(:resource_metadata, features: [], resource_id: resource.id)
    insert(:resource_metadata, features: nil, resource_id: resource.id)

    # latest metadata for the resource
    insert(:resource_metadata, features: ["vehicle_positions", "trip_updates"], resource_id: resource.id)

    # another resource linked to a single metadata
    insert(:resource_metadata,
      features: ["vehicle_positions", "service_alerts"],
      resource: insert(:resource, format: "gtfs-rt")
    )

    assert %{"service_alerts" => 1, "trip_updates" => 1, "vehicle_positions" => 2} == count_feed_types_gtfs_rt()
  end

  test "store_stats" do
    resource = insert(:resource, format: "gtfs-rt")
    insert(:resource_metadata, features: ["vehicle_positions"], resource_id: resource.id)
    insert(:resource_metadata, features: ["trip_updates"], resource_id: resource.id)
    stats = compute_stats()
    store_stats()
    assert DB.Repo.aggregate(DB.StatsHistory, :count, :id) >= Enum.count(stats)

    all_metrics = DB.StatsHistory |> select([s], s.metric) |> DB.Repo.all()

    stats_metrics =
      stats |> Map.keys() |> Enum.map(&to_string/1) |> Enum.reject(&String.starts_with?(&1, "gtfs_rt_types"))

    assert MapSet.subset?(MapSet.new(stats_metrics), MapSet.new(all_metrics))
    assert Enum.member?(all_metrics, "gtfs_rt_types::vehicle_positions")
    assert Enum.member?(all_metrics, "gtfs_rt_types::trip_updates")
  end

  test "count dataset per format" do
    inactive_dataset = insert(:dataset, is_active: false)
    insert(:resource, dataset_id: inactive_dataset.id, format: format = "xxx")

    active_dataset = insert(:dataset, is_active: true)
    insert(:resource, dataset_id: active_dataset.id, format: format)

    count_resources = count_dataset_with_format(format)

    assert count_resources == 1
  end
end
