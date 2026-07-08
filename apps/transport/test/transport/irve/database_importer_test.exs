defmodule Transport.IRVE.DatabaseImporterTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  # Mirror the consolidation flow: validate the body, cast the validated frame, checksum the raw bytes.
  defp build(content) do
    {_summary, validated_df} = Transport.IRVE.Validator.validate_and_summarize(content)
    typed_df = Transport.IRVE.Processing.cast_validated_frame(validated_df)
    checksum = Transport.IRVE.DatabaseImporter.compute_checksum(content)
    {typed_df, checksum}
  end

  test "Import new file, then import again (no change) and import with change" do
    csv_content =
      DB.Factory.IRVE.to_csv_body([DB.Factory.IRVE.generate_row(%{"id_pdc_itinerance" => "FRPAN99E87654321"})])

    {typed_df, checksum} = build(csv_content)

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
        typed_df,
        checksum,
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

    # Second import with same content should raise a constraint error
    assert_raise Ecto.ConstraintError, ~r/irve_valid_file_datagouv_resource_id_checksum_index/, fn ->
      Transport.IRVE.DatabaseImporter.write_to_db(
        typed_df,
        checksum,
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

    {updated_typed_df, updated_checksum} = build(updated_csv_content)

    {:ok, _transaction_result} =
      Transport.IRVE.DatabaseImporter.write_to_db(
        updated_typed_df,
        updated_checksum,
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
  end

  test "already_in_db?/2 matches on (resource_id, checksum)" do
    refute Transport.IRVE.DatabaseImporter.already_in_db?("resource-id", "checksum")

    DB.Repo.insert!(%DB.IRVEValidFile{
      datagouv_dataset_id: "dataset-id",
      datagouv_resource_id: "resource-id",
      checksum: "checksum"
    })

    assert Transport.IRVE.DatabaseImporter.already_in_db?("resource-id", "checksum")
    refute Transport.IRVE.DatabaseImporter.already_in_db?("resource-id", "other-checksum")
    refute Transport.IRVE.DatabaseImporter.already_in_db?("other-resource-id", "checksum")
  end
end
