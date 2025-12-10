defmodule Transport.IRVE.Validator do
  @moduledoc """
  Central entry point for IRVE file validation (currently working on `DataFrame`).
  """

  def compute_validation(%Explorer.DataFrame{} = df) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    df
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_field_validation_columns(schema)
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_row_validation_column()
  end

  @doc """
  Says from the dataframe output of compute_validation/1 if all rows are valid.
  """

  def full_file_valid?(%Explorer.DataFrame{} = df) do
    df["check_row_valid"]
    |> Explorer.Series.all?()
  end
end
