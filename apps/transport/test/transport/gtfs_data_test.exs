defmodule Transport.GTFSDataTest do
  use ExUnit.Case, async: false
  import DB.Factory
  import Ecto.Query
  import Transport.GTFSData, only: [list_views: 1]

  @cluster_views_prefix "gtfs_stops_clusters"
  @cluster_views_pattern @cluster_views_prefix <> "%"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def drop_views(pattern) do
    pattern
    |> list_views()
    |> Enum.each(fn view_name ->
      {:ok, _} = Ecto.Adapters.SQL.query(DB.Repo, "drop materialized view #{view_name}")
    end)
  end

  # input: arrays of lat/lon
  def insert_gtfs_stops(lat_lon_list) do
    dataset = insert(:dataset, %{custom_title: "Transports publics de Dehaven", is_active: true})
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

    {data_import, resource, dataset}
  end

  test "build_detailed for map" do
    {data_import, _resource, _dataset} = insert_gtfs_stops([{2.5, 48.5}])

    assert Transport.GTFSData.build_detailed({3.333333, 2.333333, 48.866667, 48.266667}) == %{
             features: [
               %{
                 geometry: %{coordinates: [48.5, 2.5], type: "Point"},
                 properties: %{
                   stop_id: "LOC:001",
                   stop_name: "L'arrêt 1",
                   di_id: data_import.id,
                   d_title: "Transports publics de Dehaven",
                   location_type: nil
                 },
                 type: "Feature"
               }
             ],
             type: "FeatureCollection"
           }
  end

  test "build_detailed for API" do
    {data_import, resource, dataset} = insert_gtfs_stops([{2.5, 48.5}])

    assert Transport.GTFSData.build_detailed({3.333333, 2.333333, 48.866667, 48.266667}, mode: :api_mode) == %{
             features: [
               %{
                 geometry: %{coordinates: [48.5, 2.5], type: "Point"},
                 properties: %{
                   stop_id: "LOC:001",
                   stop_name: "L'arrêt 1",
                   data_import_id: data_import.id,
                   dataset_id: dataset.id,
                   dataset_title: "Transports publics de Dehaven",
                   resource_id: resource.id,
                   resource_title: "GTFS.zip",
                   location_type: nil
                 },
                 type: "Feature"
               }
             ],
             type: "FeatureCollection"
           }
  end

  def get_view_data(view_name) do
    query = from(s in view_name)

    query
    |> select([:cluster_lat, :cluster_lon, :count])
    |> DB.Repo.all()
  end

  test "create_if_not_exist_materialized_views" do
    drop_views(@cluster_views_pattern)

    insert_gtfs_stops([{2.5, 48.5}])

    Transport.GTFSData.create_if_not_exist_materialized_views()

    view_names = list_views(@cluster_views_pattern)
    expected_view_names = 1..12 |> Enum.map(&"#{@cluster_views_prefix}_level_#{&1}")
    assert view_names |> Enum.sort() == expected_view_names |> Enum.sort()

    # quick litmus test to verify we have something roughly working
    view_names
    |> Enum.each(fn view_name ->
      [%{cluster_lat: _, cluster_lon: _, count: 1}] = get_view_data(view_name)
    end)
  end

  test "refresh_materialized_views" do
    drop_views(@cluster_views_pattern)
    insert_gtfs_stops([{2.5, 48.5}])
    Transport.GTFSData.create_if_not_exist_materialized_views()
    [%{count: 1}] = get_view_data(@cluster_views_prefix <> "_level_1")
    insert_gtfs_stops([{2.5, 48.5}])
    [%{count: 1}] = get_view_data(@cluster_views_prefix <> "_level_1")
    Transport.GTFSData.refresh_materialized_views()
    [%{count: 2}] = get_view_data(@cluster_views_prefix <> "_level_1")
  end

  test "build_clusters_json_encoded" do
    drop_views(@cluster_views_pattern)

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

    Transport.GTFSData.create_if_not_exist_materialized_views()

    # format is expected exactly as is, without keys (to reduce load), on the javascript side
    assert Jason.decode!(
             Transport.GTFSData.build_clusters_json_encoded(
               {3.333333, 2.333333, 48.866667, 48.266667},
               {0.5, 0.5}
             )
           ) ==
             [[2.426, 48.3398, 2], [3.0325, 48.3398, 1]]
  end

  test "build_clusters_json_encoded with no data must not raise" do
    drop_views(@cluster_views_pattern)

    insert_gtfs_stops([
      {lat = 2.5, 48.5}
    ])

    Transport.GTFSData.create_if_not_exist_materialized_views()

    # must not crash when nothing is in the bounding box
    assert Jason.decode!(
             Transport.GTFSData.build_clusters_json_encoded(
               {lat + 1, lat + 2, 48.866667, 48.266667},
               {0.5, 0.5}
             )
           ) ==
             []
  end
end
