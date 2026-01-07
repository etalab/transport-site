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

  test "A file latin1 encoded should be validated correctly" do
    simple_row =
      DB.Factory.IRVE.generate_row(%{
        # The € character can’t be transcoded in latin1
        "tarification" => "2,50 EUR / 30min puis 0,025 EUR / minute"
      })

    csv_content = [simple_row] |> DB.Factory.IRVE.to_csv_body()
    latin1_content = :unicode.characters_to_binary(csv_content, :utf8, :latin1)

    with_tmp_file(latin1_content, fn path ->
      result = Transport.IRVE.Validator.validate(path)
      assert Transport.IRVE.Validator.full_file_valid?(result)
    end)
  end
end
