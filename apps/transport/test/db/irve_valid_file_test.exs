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
        datagouv_organization_or_owner: "orphan-org",
        unlisted_since: ~D[2026-11-01],
        soft_deleted_at: ~U[2026-11-08 04:45:00Z]
      )

    insert_list(2, :irve_valid_pdc, irve_valid_file: orphan)
    insert(:irve_valid_file, datagouv_resource_id: "kept-resource-id")

    assert [
             %{
               datagouv_dataset_id: "orphan-dataset-id",
               datagouv_resource_id: "orphan-resource-id",
               dataset_title: "orphan-dataset-title",
               datagouv_organization_or_owner: "orphan-org",
               unlisted_since: ~D[2026-11-01],
               soft_deleted_at: ~U[2026-11-08 04:45:00Z],
               pdc_count: 2
             }
           ] = DB.IRVEValidFile.orphan_files(["orphan-resource-id"])

    # Providing an empty list of resource ids should return an empty list of orphan files
    assert DB.IRVEValidFile.orphan_files([]) == []
  end

  test "mark_listed/1" do
    insert(:irve_valid_file,
      datagouv_resource_id: "back",
      unlisted_since: ~D[2026-11-01],
      soft_deleted_at: ~U[2026-11-08 04:45:00Z]
    )

    insert(:irve_valid_file,
      datagouv_resource_id: "still-unlisted",
      unlisted_since: ~D[2026-11-01],
      soft_deleted_at: ~U[2026-11-08 04:45:00Z]
    )

    assert {1, nil} = DB.IRVEValidFile.mark_listed(["back"])

    assert tracking() == %{
             "back" => {nil, nil},
             "still-unlisted" => {~D[2026-11-01], ~U[2026-11-08 04:45:00Z]}
           }
  end

  test "mark_unlisted/2 keeps the first date" do
    insert(:irve_valid_file, datagouv_resource_id: "new")
    insert(:irve_valid_file, datagouv_resource_id: "already", unlisted_since: ~D[2026-11-01])
    insert(:irve_valid_file, datagouv_resource_id: "listed")

    assert {1, nil} = DB.IRVEValidFile.mark_unlisted(["new", "already"], ~D[2026-11-19])

    assert tracking() == %{
             "new" => {~D[2026-11-19], nil},
             "already" => {~D[2026-11-01], nil},
             "listed" => {nil, nil}
           }
  end

  test "soft_delete_unlisted/1 up to the cutoff date" do
    insert(:irve_valid_file, datagouv_resource_id: "before", unlisted_since: ~D[2026-11-11])
    insert(:irve_valid_file, datagouv_resource_id: "on", unlisted_since: ~D[2026-11-12])
    insert(:irve_valid_file, datagouv_resource_id: "after", unlisted_since: ~D[2026-11-13])
    insert(:irve_valid_file, datagouv_resource_id: "listed")

    insert(:irve_valid_file,
      datagouv_resource_id: "already",
      unlisted_since: ~D[2026-11-01],
      soft_deleted_at: ~U[2026-11-08 04:45:00Z]
    )

    assert {2, nil} = DB.IRVEValidFile.soft_delete_unlisted(~D[2026-11-12])

    assert %{
             "before" => {~D[2026-11-11], %DateTime{}},
             "on" => {~D[2026-11-12], %DateTime{}},
             "after" => {~D[2026-11-13], nil},
             "listed" => {nil, nil},
             "already" => {~D[2026-11-01], ~U[2026-11-08 04:45:00Z]}
           } = tracking()
  end

  defp tracking do
    DB.IRVEValidFile
    |> DB.Repo.all()
    |> Map.new(&{&1.datagouv_resource_id, {&1.unlisted_since, &1.soft_deleted_at}})
  end
end
