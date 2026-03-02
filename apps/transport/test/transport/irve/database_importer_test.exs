defmodule Transport.IRVE.DatabaseImporterTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "Import new file, then import again (no change) and import with change" do
    csv_content =
      DB.Factory.IRVE.to_csv_body([DB.Factory.IRVE.generate_row(%{"id_pdc_itinerance" => "FRPAN99E87654321"})])

    temp_path = System.tmp_dir!() |> Path.join("irve_test_#{Ecto.UUID.generate()}.csv")
    File.write!(temp_path, csv_content)

    dataset_id = "datagouv_dataset_id"
    resource_id = "datagouv_resource_id"
    dataset_title = "Bornes de recharge IRVE – mon réseau"
    organization = "SuperCharge org"
    last_modified = "2024-01-01T10:00:00+00:00"

    # First import: there is no previous version, so a new first_import_file and its PDCs are inserted.
    # Let's make sure we start from a clean state.
    assert DB.Repo.aggregate(DB.IRVEValidFile, :count, :id) == 0
    assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 0

    {:ok, _transaction_result} =
      Transport.IRVE.DatabaseImporter.write_to_db(
        temp_path,
        dataset_id,
        resource_id,
        dataset_title,
        organization,
        last_modified
      )

    first_import_file = DB.Repo.one!(DB.IRVEValidFile)
    assert first_import_file.datagouv_dataset_id == dataset_id
    assert first_import_file.datagouv_resource_id == resource_id

    [%DB.IRVEValidPDC{} = first_import_pdc] =
      DB.IRVEValidPDC
      |> where([p], p.irve_valid_file_id == ^first_import_file.id)
      |> DB.Repo.all()

    assert first_import_pdc.id_pdc_itinerance == "FRPAN99E87654321"
    refute first_import_pdc.gratuit

    # Second import with same file should raise a constraint error
    assert_raise Ecto.ConstraintError, ~r/irve_valid_file_datagouv_resource_id_checksum_index/, fn ->
      Transport.IRVE.DatabaseImporter.write_to_db(
        temp_path,
        dataset_id,
        resource_id,
        dataset_title,
        organization,
        last_modified
      )
    end

    # Third import with a change
    updated_csv_content =
      DB.Factory.IRVE.to_csv_body([
        DB.Factory.IRVE.generate_row(%{
          "id_pdc_itinerance" => "FRPAN99E87654321",
          # The change, it’s false in factories
          "gratuit" => true
        })
      ])

    File.write!(temp_path, updated_csv_content)

    {:ok, _transaction_result} =
      Transport.IRVE.DatabaseImporter.write_to_db(
        temp_path,
        dataset_id,
        resource_id,
        dataset_title,
        organization,
        last_modified
      )

    # It’s just a new file and its pdcs, the old one has been deleted. The one! would raise if there were more than one.
    second_import_file = DB.Repo.one!(DB.IRVEValidFile)
    refute first_import_file.id == second_import_file.id
    refute first_import_file.checksum == second_import_file.checksum

    # Same, this wouldn’t match if there was more than a single PDC.

    %DB.IRVEValidPDC{} = second_import_pdc = DB.Repo.one!(DB.IRVEValidPDC)

    refute first_import_pdc.id == second_import_pdc.id
    assert second_import_pdc.id_pdc_itinerance == "FRPAN99E87654321"
    assert second_import_pdc.gratuit

    File.rm(temp_path)
  end
end
