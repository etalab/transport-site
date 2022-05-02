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

  test "store_stats" do
    insert(:resource, format: "gtfs-rt", features: ["trip_updates", "vehicle_positions"])
    stats = compute_stats()
    store_stats()
    assert DB.Repo.aggregate(DB.StatsHistory, :count, :id) >= Enum.count(stats)

    all_metrics = DB.StatsHistory |> select([s], s.metric) |> DB.Repo.all()

    stats_metrics = Map.keys(stats) |> Enum.map(&to_string/1) |> Enum.reject(&String.starts_with?(&1, "gtfs_rt_types"))

    assert MapSet.subset?(MapSet.new(stats_metrics), MapSet.new(all_metrics))
    assert Enum.member?(all_metrics, "gtfs_rt_types::vehicle_positions")
    assert Enum.member?(all_metrics, "gtfs_rt_types::trip_updates")
  end
end
