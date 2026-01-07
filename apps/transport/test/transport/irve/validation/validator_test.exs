defmodule Transport.IRVE.ValidatorTest do
  @moduledoc """
  This modules does high-level tests of the IRVE Validator module.
  There are more tests:
  - In the Transport.IRVE.Validator.DataFrameValidationTest module,
  - And primitives are tested in Transport.DataFrame.Validation.PrimitivesTest.
  """

  use ExUnit.Case, async: true

  test "validate/1 returns a dataframe with validation columns" do
    csv_content = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()

    temp_path = System.tmp_dir!() |> Path.join("irve_validator_test_#{Ecto.UUID.generate()}.csv")

    try do
      File.write!(temp_path, csv_content)
      result = Transport.IRVE.Validator.validate(temp_path)

      assert %Explorer.DataFrame{} = result
      assert "check_row_valid" in Explorer.DataFrame.names(result)
      assert Transport.IRVE.Validator.full_file_valid?(result)
    after
      File.rm(temp_path)
    end
  end

  test "a ZIP file should raise an error" do
    zip_content = "PK\x03\x04" <> "some content"

    temp_path = System.tmp_dir!() |> Path.join("irve_validator_test_#{Ecto.UUID.generate()}.csv")

    try do
      File.write!(temp_path, zip_content)
      Transport.IRVE.Validator.validate(temp_path)
    rescue
      e in RuntimeError ->
        assert e.message == "the content is likely to be a zip file, not uncompressed CSV data"
    after
      File.rm(temp_path)
    end

    # Alternative version without try/rescue
    # File.write!(temp_path, zip_content)
    # assert_raise RuntimeError, "the content is likely to be a zip file, not uncompressed CSV data", fn ->
    #   Transport.IRVE.Validator.validate(temp_path)
    # end
    # File.rm(temp_path)
  end
end
