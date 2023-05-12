defmodule Transport.GTFSDataTest do
  use ExUnit.Case, async: true
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
