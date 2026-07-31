defmodule DB.IRVEValidFileTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "existing_datagouv_resource_ids_and_checksums/0 returns the set of {resource_id, checksum} pairs" do
    insert(:irve_valid_file, datagouv_resource_id: "resource-a", checksum: "checksum-a")
    insert(:irve_valid_file, datagouv_resource_id: "resource-b", checksum: "checksum-b")

    assert DB.IRVEValidFile.existing_datagouv_resource_ids_and_checksums() ==
             MapSet.new([
               {"resource-a", "checksum-a"},
               {"resource-b", "checksum-b"}
             ])
  end

  test "orphan_files/1 returns metadata and PDC count for the given resource ids only" do
    orphan =
      insert(:irve_valid_file,
        datagouv_dataset_id: "orphan-dataset-id",
        datagouv_resource_id: "orphan-resource-id",
        dataset_title: "orphan-dataset-title",
        datagouv_organization_or_owner: "orphan-org"
      )

    insert_list(2, :irve_valid_pdc, irve_valid_file: orphan)
    insert(:irve_valid_file, datagouv_resource_id: "kept-resource-id")

    assert [
             %{
               datagouv_dataset_id: "orphan-dataset-id",
               datagouv_resource_id: "orphan-resource-id",
               dataset_title: "orphan-dataset-title",
               datagouv_organization_or_owner: "orphan-org",
               pdc_count: 2
             }
           ] = DB.IRVEValidFile.orphan_files(["orphan-resource-id"])

    # Providing an empty list of resource ids should return an empty list of orphan files
    assert DB.IRVEValidFile.orphan_files([]) == []
  end
end
