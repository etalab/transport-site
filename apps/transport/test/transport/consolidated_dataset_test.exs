defmodule Transport.ConsolidatedDatasetTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "Finds the IRVE Dataset" do
    %DB.Dataset{id: dataset_id} = insert_irve_dataset()
    assert %DB.Dataset{id: ^dataset_id} = Transport.ConsolidatedDataset.dataset(:irve)
  end

  test "finds the parking relais dataset (and not BNLS)" do
    %DB.Dataset{id: dataset_id} = insert_parcs_relais_dataset()

    insert(:dataset, %{
      type: "private-parking",
      custom_title: "Base Nationale des Lieux de Stationnement",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label),
      organization_id: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)
    })

    assert %DB.Dataset{id: ^dataset_id} = Transport.ConsolidatedDataset.dataset(:parkings_relais)
  end

  test "Finds the right resource" do
    %DB.Dataset{id: dataset_id} = insert_zfe_dataset()
    insert(:resource, dataset_id: dataset_id, format: "csv", title: "Identifiants des ZFE")

    %DB.Resource{id: resource_geojson_id} =
      insert(:resource, dataset_id: dataset_id, format: "geojson", title: "aires.geojson")

    assert %DB.Resource{id: ^resource_geojson_id} = Transport.ConsolidatedDataset.resource(:zfe)
  end
end
