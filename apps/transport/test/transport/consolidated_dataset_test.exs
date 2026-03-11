defmodule Transport.ConsolidatedDatasetTest do
  # The trigger refresh_dataset_geographic_view_trigger makes this test
  # unreliable in a concurrent setup.
  use ExUnit.Case, async: false
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "Finds the IRVE Dataset" do
    %DB.Dataset{id: dataset_id} = insert_irve_dataset()
    assert %DB.Dataset{id: ^dataset_id} = Transport.ConsolidatedDataset.dataset(:irve)
  end

  test "Finds the right resource" do
    %DB.Dataset{id: dataset_id} = insert_zfe_dataset()
    insert(:resource, dataset_id: dataset_id, format: "csv", title: "Identifiants des ZFE")

    %DB.Resource{id: resource_geojson_id} =
      insert(:resource, dataset_id: dataset_id, format: "geojson", title: "aires.geojson")

    assert %DB.Resource{id: ^resource_geojson_id} = Transport.ConsolidatedDataset.resource(:zfe)
  end
end
