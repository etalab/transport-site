# mix run scripts/irve/validate_and_import_local_file.exs
# This allows to test validation and import of a local file without all the rescueing logic.
# If something raises, great! You’ve found a bug to fix :)

import Ecto.Query

# Change me
file_path = "mobilize.csv"

Transport.LogTimeTaken.log_time_taken("Validating #{file_path}", fn ->
  IO.puts("Starting validating (#{file_path})…")

  body = File.read!(file_path)
  {summary, validated_df} = Transport.IRVE.Validator.validate_and_summarize(body)

  IO.inspect(summary, IEx.inspect_opts())

  # Now trying to import
  Transport.LogTimeTaken.log_time_taken("Importing #{file_path}", fn ->
    IO.puts("Starting importing (#{file_path})…")

    typed_df = Transport.IRVE.Processing.cast_validated_frame(validated_df)
    checksum = Transport.IRVE.DatabaseImporter.compute_checksum(body)

    Transport.IRVE.DatabaseImporter.write_to_db(
      typed_df,
      checksum,
      "test-dataset-id",
      "test-resource-id",
      "test-title",
      "test-org",
      "2024-01-01T00:00:00+00:00"
    )

    IO.puts("Importing done.")
  end)

  # Verifying import

  file =
    DB.IRVEValidFile
    |> DB.Repo.get_by!(datagouv_dataset_id: "test-dataset-id", datagouv_resource_id: "test-resource-id")

  file_id = file.id

  pdc_count =
    DB.IRVEValidPDC |> where(irve_valid_file_id: ^file_id) |> DB.Repo.aggregate(:count, :id)

  IO.puts("Imported PDC count: #{pdc_count}")
  first_pdc = DB.IRVEValidPDC |> where(irve_valid_file_id: ^file_id) |> first() |> DB.Repo.one()
  IO.puts("First imported PDC:")
  IO.inspect(first_pdc)
  DB.Repo.delete(file)
end)
