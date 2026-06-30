defmodule Transport.IRVE.ValidatorTest do
  @moduledoc """
  This modules does high-level tests of the IRVE Validator module.
  There are more tests:
  - In the Transport.IRVE.Validator.DataFrameValidationTest module,
  - And primitives are tested in Transport.DataFrame.Validation.PrimitivesTest.
  """

  use ExUnit.Case, async: true
  import Transport.TmpFile

  test "validate_and_summarize/1 returns a valid summary for a valid file" do
    csv_content = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert %Transport.IRVE.Validator.Summary{
               valid: true,
               valid_row_count: 1,
               invalid_row_count: 0,
               total_row_count: 1,
               file_level_errors: [],
               column_errors: %{},
               error_samples: [],
               warnings: %{},
               warning_samples: []
             } == Transport.IRVE.Validator.validate_and_summarize(path)
    end)
  end

  test "a ZIP file is reported as a file-level error" do
    with_tmp_file(_zip_content = "PK\x03\x04" <> "some content", fn path ->
      assert %{valid: false, file_level_errors: [message]} =
               Transport.IRVE.Validator.validate_and_summarize(path)

      assert message =~ "content is likely to be a zip file"
    end)
  end

  test "a non-CSV file is reported as a file-level error" do
    with_tmp_file("non-csv-content", fn path ->
      assert %{valid: false, file_level_errors: ["the content is likely not a CSV file (extension is .pdf)"]} =
               Transport.IRVE.Validator.validate_and_summarize(path, ".pdf")
    end)
  end

  test "A schema V1 file is reported as a file-level error" do
    v1_like_row =
      DB.Factory.IRVE.generate_row()
      |> Map.put("n_operateur", Map.get(DB.Factory.IRVE.generate_row(), "nom_operateur"))
      |> Map.delete("nom_operateur")

    csv_content = [v1_like_row] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert %{valid: false, file_level_errors: ["looks like a v1 irve"]} =
               Transport.IRVE.Validator.validate_and_summarize(path)
    end)
  end

  test "A file without id_pdc_itinerance is reported as a file-level error" do
    v1_like_row =
      DB.Factory.IRVE.generate_row()
      |> Map.put("id_pdc", Map.get(DB.Factory.IRVE.generate_row(), "id_pdc_itinerance"))
      |> Map.delete("id_pdc_itinerance")

    csv_content = [v1_like_row] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert %{valid: false, file_level_errors: ["content has no id_pdc_itinerance in first line"]} =
               Transport.IRVE.Validator.validate_and_summarize(path)
    end)
  end

  test "A file with a tabulation as separator is reported as a file-level error" do
    csv_content =
      [DB.Factory.IRVE.generate_row()]
      |> CSV.encode(separator: ?\t, delimiter: "\n", headers: true)
      |> Enum.join()

    with_tmp_file(csv_content, fn path ->
      assert %{valid: false, file_level_errors: ["unsupported column separator \t"]} =
               Transport.IRVE.Validator.validate_and_summarize(path)
    end)
  end

  test "A Latin-1-encoded file should be considered valid & its data transcoded to UTF-8" do
    # `é` is encoded differently in UTF-8 vs Latin-1, allowing us to verify transcoding
    # `€` doesn't exist in Latin-1, so we use `EUR` instead
    row =
      DB.Factory.IRVE.generate_row(%{
        "nom_station" => "Ma station accentuée",
        "tarification" => "2,50 EUR / 30min puis 0,025 EUR / minute"
      })

    latin1_content = [row] |> DB.Factory.IRVE.to_csv_body() |> :unicode.characters_to_binary(:utf8, :latin1)
    # sanity check that we actually have Latin-1 byte for the accent
    assert latin1_content =~ <<"Ma station accentu", 0xE9, "e">>

    with_tmp_file(latin1_content, fn path ->
      assert Transport.IRVE.Validator.validate_and_summarize(path).valid
    end)
  end

  test "A file with a semicolon as separator should be validated correctly" do
    csv_content =
      [DB.Factory.IRVE.generate_row()]
      |> CSV.encode(separator: ?;, headers: true)
      |> Enum.join()

    with_tmp_file(csv_content, fn path ->
      assert Transport.IRVE.Validator.validate_and_summarize(path).valid
    end)
  end

  test "A file with a missing optional column should be validated correctly" do
    csv_content =
      [
        DB.Factory.IRVE.generate_row() |> Map.delete("tarification")
      ]
      |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert Transport.IRVE.Validator.validate_and_summarize(path).valid
    end)
  end

  test "A file with a faulty boolean should be validated correctly" do
    csv_content =
      [
        DB.Factory.IRVE.generate_row(%{"prise_type_ef" => "VRAI"})
      ]
      |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert Transport.IRVE.Validator.validate_and_summarize(path).valid
    end)
  end

  test "validate_and_summarize/1 reports column errors and caps error samples to 5 per column" do
    # 10 rows with invalid puissance_nominale, 1 row with invalid nbre_pdc (valid puissance_nominale)
    invalid_puissance_rows = for _ <- 1..10, do: DB.Factory.IRVE.generate_row(%{"puissance_nominale" => "not-a-number"})
    invalid_nbre_pdc_row = DB.Factory.IRVE.generate_row(%{"nbre_pdc" => "not-a-number"})
    csv_content = (invalid_puissance_rows ++ [invalid_nbre_pdc_row]) |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      summary = Transport.IRVE.Validator.validate_and_summarize(path)

      assert summary.valid == false
      assert summary.valid_row_count == 0
      assert summary.invalid_row_count == 11
      assert summary.column_errors == %{"puissance_nominale" => 10, "nbre_pdc" => 1}

      # 5 samples from puissance_nominale (capped) + 1 from nbre_pdc
      assert length(summary.error_samples) == 6

      assert summary.error_samples
             |> Enum.filter(&(&1.column == "puissance_nominale"))
             |> Enum.all?(&(&1.value == "not-a-number"))

      assert [%{column: "nbre_pdc", value: "not-a-number", id_pdc_itinerance: _}] =
               Enum.filter(summary.error_samples, &(&1.column == "nbre_pdc"))
    end)
  end

  test "validate_and_summarize/1 reports inverted lon/lat coordinates as a warning" do
    inverted_row =
      DB.Factory.IRVE.generate_row(%{
        "id_pdc_itinerance" => "FRPAN99E00000001",
        "coordonneesXY" => "[45.91914, -0.799141]"
      })

    valid_row = DB.Factory.IRVE.generate_row()
    csv_content = [inverted_row, valid_row] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      summary = Transport.IRVE.Validator.validate_and_summarize(path)

      assert summary.valid == true
      assert summary.column_errors == %{}
      assert summary.warnings == %{"lon_lat_inverted" => 1}

      assert summary.warning_samples == [
               %{id_pdc_itinerance: "FRPAN99E00000001", warning: "lon_lat_inverted", value: "[45.91914, -0.799141]"}
             ]
    end)
  end

  test "validate_and_summarize/1 returns a normal summary with file_level_error: nil for a valid file" do
    csv_content = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      summary = Transport.IRVE.Validator.validate_and_summarize(path)

      assert %{valid: true, valid_row_count: 1, invalid_row_count: 0, file_level_errors: []} = summary
    end)
  end

  test "validate_and_summarize/1 returns an error summary instead of raising on a file-level error" do
    with_tmp_file("PK\x03\x04" <> "some content", fn path ->
      summary = Transport.IRVE.Validator.validate_and_summarize(path)

      assert %{
               valid: false,
               valid_row_count: nil,
               invalid_row_count: nil,
               total_row_count: nil,
               file_level_errors: [error_message],
               column_errors: %{},
               error_samples: []
             } = summary

      assert error_message =~ "zip"
    end)
  end

  test "validate_and_summarize/1 returns a summary (no raise) on an unexpected downstream error" do
    # passes every file-level probe (has id_pdc_itinerance, comma-separated, .csv, v2 schema)
    # but a required column is missing, which blows up deeper in the validation pipeline
    csv_content =
      [DB.Factory.IRVE.generate_row() |> Map.delete("nom_station")]
      |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      summary = Transport.IRVE.Validator.validate_and_summarize(path)

      assert %Transport.IRVE.Validator.Summary{
               valid: false,
               valid_row_count: nil,
               invalid_row_count: nil,
               total_row_count: nil,
               column_errors: %{},
               error_samples: [],
               file_level_errors: [message]
             } = summary

      # marked as unexpected (vs a known schema-level problem) ...
      assert String.starts_with?(message, "Unexpected error: ")
      # ... and the full message also lists every available column, which is too brittle to assert on
      assert message =~ ~s|could not find column name "nom_station"|
    end)
  end
end
