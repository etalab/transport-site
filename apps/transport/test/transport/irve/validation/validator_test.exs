defmodule Transport.IRVE.ValidatorTest do
  @moduledoc """
  This modules does high-level tests of the IRVE Validator module.
  There are more tests:
  - In the Transport.IRVE.Validator.DataFrameValidationTest module,
  - And primitives are tested in Transport.DataFrame.Validation.PrimitivesTest.
  """

  use ExUnit.Case, async: true
  import Transport.TmpFile

  test "validate/1 returns a dataframe with validation columns" do
    csv_content = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      result = Transport.IRVE.Validator.validate(path)

      assert %Explorer.DataFrame{} = result
      assert "check_row_valid" in Explorer.DataFrame.names(result)
      assert Transport.IRVE.Validator.full_file_valid?(result)
    end)
  end

  test "a ZIP file should raise an error" do
    with_tmp_file(_zip_content = "PK\x03\x04" <> "some content", fn path ->
      assert_raise RuntimeError, ~r/content is likely to be a zip file/, fn ->
        Transport.IRVE.Validator.validate(path)
      end
    end)
  end

  test "a non-CSV file should raise an error" do
    with_tmp_file("non-csv-content", fn path ->
      assert_raise RuntimeError, "the content is likely not a CSV file (extension is .pdf)", fn ->
        Transport.IRVE.Validator.validate(path, ".pdf")
      end
    end)
  end

  test "A schema V1 file should raise an error" do
    v1_like_row =
      DB.Factory.IRVE.generate_row()
      |> Map.put("n_operateur", Map.get(DB.Factory.IRVE.generate_row(), "nom_operateur"))
      |> Map.delete("nom_operateur")

    csv_content = [v1_like_row] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert_raise RuntimeError, "looks like a v1 irve", fn ->
        Transport.IRVE.Validator.validate(path)
      end
    end)
  end

  test "A file without id_pdc_itinerance should raise an error" do
    v1_like_row =
      DB.Factory.IRVE.generate_row()
      |> Map.put("id_pdc", Map.get(DB.Factory.IRVE.generate_row(), "id_pdc_itinerance"))
      |> Map.delete("id_pdc_itinerance")

    csv_content = [v1_like_row] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      assert_raise RuntimeError, "content has no id_pdc_itinerance in first line", fn ->
        Transport.IRVE.Validator.validate(path)
      end
    end)
  end

  test "A file with a tabulation as separator should raise an error" do
    csv_content =
      [DB.Factory.IRVE.generate_row()]
      |> CSV.encode(separator: ?\t, delimiter: "\n", headers: true)
      |> Enum.join()

    with_tmp_file(csv_content, fn path ->
      assert_raise RuntimeError, "unsupported column separator \t", fn ->
        Transport.IRVE.Validator.validate(path)
      end
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
      result = Transport.IRVE.Validator.validate(path)
      assert Transport.IRVE.Validator.full_file_valid?(result)
      # and here we're back to UTF-8
      assert result["nom_station"] |> Explorer.Series.to_list() == ["Ma station accentuée"]
    end)
  end

  test "A file with a semicolon as separator should be validated correctly" do
    csv_content =
      [DB.Factory.IRVE.generate_row()]
      |> CSV.encode(separator: ?;, headers: true)
      |> Enum.join()

    with_tmp_file(csv_content, fn path ->
      result = Transport.IRVE.Validator.validate(path)
      assert Transport.IRVE.Validator.full_file_valid?(result)
    end)
  end

  test "A file with a missing optional column should be validated correctly" do
    csv_content =
      [
        DB.Factory.IRVE.generate_row() |> Map.delete("tarification")
      ]
      |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      result = Transport.IRVE.Validator.validate(path)
      assert Transport.IRVE.Validator.full_file_valid?(result)
    end)
  end

  test "A file with a faulty boolean should be validated correctly" do
    csv_content =
      [
        DB.Factory.IRVE.generate_row(%{"prise_type_ef" => "VRAI"})
      ]
      |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      result = Transport.IRVE.Validator.validate(path)
      assert Transport.IRVE.Validator.full_file_valid?(result)
    end)
  end

  test "summarize/1 returns a valid summary for a valid file" do
    csv_content = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      summary = Transport.IRVE.Validator.validate(path) |> Transport.IRVE.Validator.summarize()

      assert %{
               valid: true,
               valid_row_count: 1,
               invalid_row_count: 0,
               column_errors: %{},
               error_samples: []
             } = summary
    end)
  end

  test "summarize/1 reports column errors and caps error samples to 5 per column" do
    # 10 rows with invalid puissance_nominale, 1 row with invalid nbre_pdc (valid puissance_nominale)
    invalid_puissance_rows = for _ <- 1..10, do: DB.Factory.IRVE.generate_row(%{"puissance_nominale" => "not-a-number"})
    invalid_nbre_pdc_row = DB.Factory.IRVE.generate_row(%{"nbre_pdc" => "not-a-number"})
    csv_content = (invalid_puissance_rows ++ [invalid_nbre_pdc_row]) |> DB.Factory.IRVE.to_csv_body()

    with_tmp_file(csv_content, fn path ->
      summary = Transport.IRVE.Validator.validate(path) |> Transport.IRVE.Validator.summarize()

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
end
