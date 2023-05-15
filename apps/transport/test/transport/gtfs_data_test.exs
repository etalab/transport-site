defmodule Transport.GTFSDataTest do
  use ExUnit.Case, async: false
  import DB.Factory
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  # not to be used outside test (SQL injection)
  def list_views(pattern) do
    {:ok, %{rows: view_names}} =
      Ecto.Adapters.SQL.query(
        DB.Repo,
        "select matviewname from pg_matviews where matviewname like '#{pattern}'"
      )

    List.flatten(view_names)
  end

  # input: arrays of lat/lon
  def insert_gtfs_stops(lat_lon_list) do
    dataset = insert(:dataset, %{custom_title: "Hello", is_active: true})
    resource = insert(:resource, dataset: dataset)
    resource_history = insert(:resource_history, resource: resource)
    data_import = insert(:data_import, resource_history: resource_history)

    lat_lon_list
    |> Enum.with_index()
    |> Enum.each(fn {{lat, lon}, index} ->
      index = index + 1

      insert(:gtfs_stops,
        data_import: data_import,
        stop_lat: lat,
        stop_lon: lon,
        stop_name: "L'arrêt #{index}",
        stop_id: "LOC:#{String.pad_leading(index |> Integer.to_string(), 3, "0")}"
      )
    end)

    data_import
  end

  test "build_detailed" do
    data_import = insert_gtfs_stops([{2.5, 48.5}])

    assert Transport.GTFSData.build_detailed({3.333333, 2.333333, 48.866667, 48.266667}) == %{
             features: [
               %{
                 geometry: %{coordinates: [48.5, 2.5], type: "Point"},
                 properties: %{
                   d_id: data_import.id,
                   d_title: "Hello",
                   stop_id: "LOC:001",
                   stop_location_type: nil
                 },
                 type: "Feature"
               }
             ],
             type: "FeatureCollection"
           }
  end

  test "create_if_not_exist_materialized_views" do
    list_views("gtfs_stops_clusters%")
    |> Enum.each(fn view_name ->
      {:ok, _} = Ecto.Adapters.SQL.query(DB.Repo, "drop materialized view #{view_name}")
    end)

    insert_gtfs_stops([{2.5, 48.5}])

    Transport.GTFSData.create_it_not_exist_materialized_views()

    view_names = list_views("gtfs_stops_clusters%")
    expected_view_names = 1..12 |> Enum.map(&"gtfs_stops_clusters_level_#{&1}")
    assert view_names == expected_view_names

    # quick litmus test to verify we have something roughly working
    view_names
    |> Enum.each(fn view_name ->
      [%{cluster_lat: _, cluster_lon: _, count: 1}] =
        from(s in view_name)
        |> select([:cluster_lat, :cluster_lon, :count])
        |> DB.Repo.all()
    end)
  end

  test "refresh_materialized_views" do
  end

  test "build_clusters_json_encoded" do
    drop_views(@cluster_views_prefix <> "%")

    insert_gtfs_stops([
      {2.5, 48.5},
      {2.6, 48.6},
      {3.3, 48.6}
    ])

    # the views must not be created lazily anymore
    assert_raise(Postgrex.Error, ~r/undefined_table/, fn ->
      Transport.GTFSData.build_clusters_json_encoded(
        {3.333333, 2.333333, 48.866667, 48.266667},
        {0.5, 0.5}
      )
    end)

    Transport.GTFSData.create_it_not_exist_materialized_views()

    # format is expected exactly as is, without keys (to reduce load), on the javascript side
    assert Jason.decode!(
             Transport.GTFSData.build_clusters_json_encoded(
               {3.333333, 2.333333, 48.866667, 48.266667},
               {0.5, 0.5}
             )
           ) ==
             [[2.426, 48.3398, 2], [3.0325, 48.3398, 1]]
  end
end
