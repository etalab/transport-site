# mix run scripts/irve/validate_and_import_local_file.exs
# This allows to test validation and import of a local file without all the rescueing logic.
# If something raises, great! You’ve found a bug to fix :)

import Ecto.Query

# Change me
file_path = "mobilize.csv"

Transport.LogTimeTaken.log_time_taken("Validating #{file_path}", fn ->
  IO.puts("Starting validating (#{file_path})…")
  df = Transport.IRVE.Validator.validate(file_path)

  IO.puts("Is the full file valid? #{df |> Transport.IRVE.Validator.full_file_valid?()}")

  IO.puts("Validation summary (how many rows are valid or invalid):")

  df["check_row_valid"]
  |> Explorer.Series.frequencies()
  |> IO.inspect(IEx.inspect_opts())

  report_columns = Transport.IRVE.StaticIRVESchema.field_names_list() |> Enum.map(&"check_column_#{&1}_valid")

  columns_with_false =
    report_columns
    |> Enum.reject(fn col ->
      df[col]
      |> Explorer.Series.all?()
    end)

  IO.puts("Columns with at least one invalid value: #{inspect(columns_with_false)}")

  report_path = Path.rootname(file_path) <> "-validation-report.csv"
  IO.puts("Writing validation report to #{report_path}")

  df |> Explorer.DataFrame.to_csv!(report_path)

  # Now trying to import
  Transport.LogTimeTaken.log_time_taken("Importing #{file_path}", fn ->
    IO.puts("Starting importing (#{file_path})…")

    Transport.IRVE.DatabaseImporter.write_to_db(
      file_path,
      "test-dataset-id",
      "test-resource-id"
    )

    IO.puts("Importing done.")
  end)

  # Verifying import

  file =
    DB.IRVEValidFile
    |> DB.Repo.get_by!(dataset_datagouv_id: "test-dataset-id", resource_datagouv_id: "test-resource-id")

  file_id = file.id

  pdc_count =
    DB.IRVEValidPDC |> where(irve_valid_file_id: ^file_id) |> DB.Repo.aggregate(:count, :id)

  IO.puts("Imported PDC count: #{pdc_count}")
  first_pdc = DB.IRVEValidPDC |> where(irve_valid_file_id: ^file_id) |> first() |> DB.Repo.one()
  IO.puts("First imported PDC:")
  IO.inspect(first_pdc)
  DB.Repo.delete(file)
end)
