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
end
