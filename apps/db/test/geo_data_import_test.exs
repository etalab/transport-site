defmodule DB.GeoDataImportTest do
  use ExUnit.Case
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "find the latest import" do
    dataset_id = 100
    now = DateTime.utc_now()
    now_100 = now |> DateTime.add(-100)
    now_50 = now |> DateTime.add(-50)
    now_25 = now |> DateTime.add(-25)

    %{id: id_0} = insert(:resource_history, %{inserted_at: now_100, payload: %{"dataset_id" => dataset_id}})
    %{id: id_1} = insert(:resource_history, %{inserted_at: now_50, payload: %{"dataset_id" => dataset_id}})
    insert(:resource_history, %{inserted_at: now_25, payload: %{"dataset_id" => 99}})

    # import a resource history linked to dataset 100
    %{id: geo_data_import_1} = insert(:geo_data_import, %{resource_history_id: id_0})

    assert is_nil(DB.GeoDataImport.dataset_latest_geo_data_import(99))

    assert %{id: ^geo_data_import_1, resource_history_id: ^id_0} =
             DB.GeoDataImport.dataset_latest_geo_data_import(dataset_id)

    # import a more recent resource history
    %{id: geo_data_import_2} = insert(:geo_data_import, %{resource_history_id: id_1})

    assert %{id: ^geo_data_import_2, resource_history_id: ^id_1} =
             DB.GeoDataImport.dataset_latest_geo_data_import(dataset_id)
  end
end
