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

    dataset_id = "dataset_datagouv_id"
    resource_id = "resource_datagouv_id"

    # First import: there is no previous version, so a new first_import_file and its PDCs are inserted
    assert DB.Repo.aggregate(DB.IRVEValidFile, :count, :id) == 0
    assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 0

    {:ok, _transaction_result} = Transport.IRVE.DatabaseImporter.write_to_db(temp_path, dataset_id, resource_id)

    first_import_file = DB.Repo.one!(DB.IRVEValidFile)
    assert first_import_file.dataset_datagouv_id == dataset_id
    assert first_import_file.resource_datagouv_id == resource_id

    [%DB.IRVEValidPDC{} = first_import_pdc] =
      DB.IRVEValidPDC
      |> where([p], p.irve_valid_file_id == ^first_import_file.id)
      |> DB.Repo.all()

    assert first_import_pdc.id_pdc_itinerance == "FRPAN99E87654321"
    refute first_import_pdc.gratuit

    # Second import with same first_import_file should return :no_change
    result = Transport.IRVE.DatabaseImporter.write_to_db(temp_path, dataset_id, resource_id)
    assert result == :no_change
    assert DB.Repo.aggregate(DB.IRVEValidFile, :count, :id) == 1
    assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 1
    assert DB.Repo.one!(DB.IRVEValidPDC).id == first_import_pdc.id

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

    {:ok, _transaction_result} = Transport.IRVE.DatabaseImporter.write_to_db(temp_path, dataset_id, resource_id)

    second_import_file = DB.Repo.one!(DB.IRVEValidFile)
    assert first_import_file.id == second_import_file.id
    refute first_import_file.checksum == second_import_file.checksum

    [%DB.IRVEValidPDC{} = second_import_pdc] =
      DB.IRVEValidPDC
      |> where([p], p.irve_valid_file_id == ^first_import_file.id)
      |> DB.Repo.all()

    refute first_import_pdc.id == second_import_pdc.id
    assert second_import_pdc.id_pdc_itinerance == "FRPAN99E87654321"
    assert second_import_pdc.gratuit

    File.rm(temp_path)
  end
end
