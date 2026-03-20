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
  Validate an IRVE file located at `path`, returning a DataFrame with validation results.
  This wrapper includes some pre-processing steps before actual validation.
  These preprocessing steps do not output any warning and are silent,
  so files that are not strictly valid may be considered as valid without any notice by this function.
  If you want to call a strict validator (no preprocessing), use `compute_validation/1` instead.
  """
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

  @doc """
  Produces a human-actionable summary from the validated DataFrame returned by `compute_validation/1`.
  Still an Elixir map, but the content should allow someone to know how to correct an invalid file.

  Returns a map with:
  - `valid` - whether the file is fully valid
  - `valid_row_count` - number of valid rows
  - `invalid_row_count` - number of invalid rows
  - `column_errors` - map of field name => number of invalid rows for that column (only columns with at least one error)
  - `error_samples` - up to 5 sample errors per errored column, each with `id_pdc_itinerance`, `column`, and `value`
  """
  def summarize(%Explorer.DataFrame{} = df) do
    {valid_count, invalid_count} = summarize_total_counts(df)
    column_errors = summarize_column_errors(df)
    error_samples = error_samples(df, column_errors)

    %{
      valid: invalid_count == 0,
      valid_row_count: valid_count,
      invalid_row_count: invalid_count,
      column_errors: column_errors,
      error_samples: error_samples
    }
  end

  @doc """
  Combines `validate/2` and `summarize/1` into a single call, catching any file-level error
  (bad encoding, wrong format, missing columns, etc.) instead of raising.

  Returns the same map as `summarize/1` with an additional `file_level_error` key:
  - `nil` when validation ran successfully (the file could still be invalid row-by-row)
  - an error message string when a hard file-level error was caught

  On a file-level error, `valid_row_count`, `invalid_row_count`, `column_errors`, and
  `error_samples` are all `nil`/empty since there is no DataFrame to summarize from.
  """
  def validate_and_summarize(path, extension \\ ".csv") do
    path
    |> validate(extension)
    |> summarize()
    |> Map.put(:file_level_error, nil)
  rescue
    error ->
      %{
        valid: false,
        file_level_error: Exception.message(error),
        valid_row_count: nil,
        invalid_row_count: nil,
        column_errors: %{},
        error_samples: []
      }
  end

  defp summarize_total_counts(df) do
    valid_count = df["check_row_valid"] |> Explorer.Series.sum()
    invalid_count = Explorer.DataFrame.n_rows(df) - valid_count
    {valid_count, invalid_count}
  end

  defp summarize_column_errors(df) do
    Transport.IRVE.StaticIRVESchema.field_names_list()
    |> Enum.map(fn field_name -> {field_name, "check_column_#{field_name}_valid"} end)
    |> Enum.flat_map(fn {field_name, check_col} ->
      error_count = df[check_col] |> Explorer.Series.not() |> Explorer.Series.sum()
      if error_count > 0, do: [{field_name, error_count}], else: []
    end)
    |> Map.new()
  end

  defp error_samples(df, column_errors) do
    column_errors
    |> Enum.flat_map(fn {field_name, _error_count} ->
      check_col = "check_column_#{field_name}_valid"

      df
      |> Explorer.DataFrame.filter_with(&(&1[check_col] |> Explorer.Series.not()))
      |> Explorer.DataFrame.select(["id_pdc_itinerance", field_name])
      # Limit to 5 samples per error column
      |> Explorer.DataFrame.head(5)
      |> Explorer.DataFrame.to_rows()
      |> Enum.map(fn row ->
        %{id_pdc_itinerance: row["id_pdc_itinerance"], column: field_name, value: row[field_name]}
      end)
    end)
  end
end
