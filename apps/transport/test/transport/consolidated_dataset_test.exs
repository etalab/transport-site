defmodule Transport.ConsolidatedDatasetTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "Finds the IRVE Dataset" do
    %DB.Dataset{id: dataset_id} = insert_irve_dataset()
    assert %DB.Dataset{id: ^dataset_id} = Transport.ConsolidatedDataset.irve_dataset()
  end

  test "finds the parking relais dataset (and not BNLS)" do
    %DB.Dataset{id: dataset_id} = insert_parcs_relais_dataset()

    insert(:dataset, %{
      type: "private-parking",
      custom_title: "Base Nationale des Lieux de Stationnement",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
    })

    assert %DB.Dataset{id: ^dataset_id} = Transport.ConsolidatedDataset.parkings_relais_dataset()
  end
end
