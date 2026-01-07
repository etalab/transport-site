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
end
