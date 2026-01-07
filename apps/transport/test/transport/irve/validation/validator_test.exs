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
end
