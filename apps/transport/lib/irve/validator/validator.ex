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

  def validate(path, extension \\ ".csv") do
    # NOTE: for now, load the body in memory, because refactoring to get full streaming
    # is too involved for the current sprint deadline.
    body = File.read!(path)
    Transport.IRVE.RawStaticConsolidation.run_cheap_blocking_checks(body, extension)
    # TODO: accumulate warnings
    body = Transport.IRVE.RawStaticConsolidation.ensure_utf8(body)
    # TODO: accumulate warnings

    body
    |> Transport.IRVE.Processing.read_as_uncasted_data_frame()
    |> compute_validation()
  end

  @doc """
  Says from the dataframe output of compute_validation/1 if all rows are valid.
  """
  def full_file_valid?(%Explorer.DataFrame{} = df) do
    df["check_row_valid"]
    |> Explorer.Series.all?()
  end
end
