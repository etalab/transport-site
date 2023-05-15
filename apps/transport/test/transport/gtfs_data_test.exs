defmodule Transport.GTFSDataTest do
  use ExUnit.Case, async: false
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "build_detailed" do
    dataset = insert(:dataset, %{custom_title: "Hello", is_active: true})
    resource = insert(:resource, dataset: dataset)
    resource_history = insert(:resource_history, resource: resource)
    data_import = insert(:data_import, resource_history: resource_history)

    insert(:gtfs_stops,
      data_import: data_import,
      stop_lat: 2.5,
      stop_lon: 48.5,
      stop_name: "L'arrêt",
      stop_id: "LOC:001"
    )

    assert Transport.GTFSData.build_detailed({3.333333, 2.333333, 48.866667, 48.266667}) == %{
             features: [
               %{
                 geometry: %{coordinates: [48.5, 2.5], type: "Point"},
                 properties: %{d_id: data_import.id, d_title: "Hello", stop_id: "LOC:001", stop_location_type: nil},
                 type: "Feature"
               }
             ],
             type: "FeatureCollection"
           }
  end

  test "create_if_not_exist_materialized_views" do
    # drop first for testing purposes
    # TODO: move to ecto, and move to helper module
    {:ok, %{rows: view_names}} =
      Ecto.Adapters.SQL.query(
        DB.Repo,
        "select matviewname from pg_matviews where matviewname like 'gtfs_stops_clusters%'"
      )

    view_names
    |> Enum.each(fn view_name ->
      {:ok, _} = Ecto.Adapters.SQL.query(DB.Repo, "drop materialized view #{view_name}")
    end)

    # TODO: move to helper code & DRY
    # We need at least one point for the method to work (bounding box)
    dataset = insert(:dataset, %{custom_title: "Hello", is_active: true})
    resource = insert(:resource, dataset: dataset)
    resource_history = insert(:resource_history, resource: resource)
    data_import = insert(:data_import, resource_history: resource_history)

    insert(:gtfs_stops,
      data_import: data_import,
      stop_lat: 2.5,
      stop_lon: 48.5,
      stop_name: "L'arrêt",
      stop_id: "LOC:001"
    )

    Transport.GTFSData.create_it_not_exist_materialized_views()

    # TODO: move to ecto, and move to helper module
    {:ok, %{rows: view_names}} =
      Ecto.Adapters.SQL.query(
        DB.Repo,
        "select matviewname from pg_matviews where matviewname like 'gtfs_stops_clusters%'"
      )

    assert view_names == [
             ["gtfs_stops_clusters_level_1"],
             ["gtfs_stops_clusters_level_2"],
             ["gtfs_stops_clusters_level_3"],
             ["gtfs_stops_clusters_level_4"],
             ["gtfs_stops_clusters_level_5"],
             ["gtfs_stops_clusters_level_6"],
             ["gtfs_stops_clusters_level_7"],
             ["gtfs_stops_clusters_level_8"],
             ["gtfs_stops_clusters_level_9"],
             ["gtfs_stops_clusters_level_10"],
             ["gtfs_stops_clusters_level_11"],
             ["gtfs_stops_clusters_level_12"]
           ]
  end

  test "build_clusters_json_encoded" do
    dataset = insert(:dataset, %{custom_title: "Hello", is_active: true})
    resource = insert(:resource, dataset: dataset)
    resource_history = insert(:resource_history, resource: resource)
    data_import = insert(:data_import, resource_history: resource_history)

    insert(:gtfs_stops,
      data_import: data_import,
      stop_lat: 2.5,
      stop_lon: 48.5,
      stop_name: "L'arrêt",
      stop_id: "LOC:001"
    )

    insert(:gtfs_stops,
      data_import: data_import,
      stop_lat: 2.6,
      stop_lon: 48.6,
      stop_name: "L'autre arrêt",
      stop_id: "LOC:002"
    )

    insert(:gtfs_stops,
      data_import: data_import,
      stop_lat: 3.3,
      stop_lon: 48.6,
      stop_name: "Encore un autre arrêt",
      stop_id: "LOC:002"
    )

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
