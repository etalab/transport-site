defmodule Transport.IRVE.Validator do
  @moduledoc """
  Central entry point for IRVE file validation (currently working on `DataFrame`).
  """

  @unexpected_error_prefix "Unexpected error: "

  def compute_validation(%Explorer.DataFrame{} = df) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    df
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_field_validation_columns(schema)
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_row_validation_column()
    |> Transport.IRVE.Validator.DataFrameValidation.setup_computed_warning_columns()
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
    Transport.IRVE.Static.Probes.run_cheap_blocking_checks(body, extension)
    validate_body(body)
  end

  @doc """
  Validate an already-loaded in-memory body, returning a DataFrame with validation results.

  Unlike `validate/2`, this does not run the cheap file-level probes: callers that need
  those should go through `validate_and_summarize/2`.
  """
  def validate_body(body) do
    # TODO: accumulate warnings
    body = Transport.IRVE.Transcoder.ensure_utf8(body)
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
    warnings = summarize_warnings(df)

    %Transport.IRVE.Validator.Summary{
      valid: invalid_count == 0,
      valid_row_count: valid_count,
      invalid_row_count: invalid_count,
      total_row_count: valid_count + invalid_count,
      file_level_errors: [],
      column_errors: column_errors,
      error_samples: error_samples,
      warnings: warnings,
      warning_samples: warning_samples(df, warnings)
    }
  end

  @doc """
  The non-raising entry point for IRVE validation: turns a file into a `%Summary{}`.

  Known file-level problems (zip, wrong format, v1 schema, …) are detected up-front by
  `Transport.IRVE.Static.Probes.file_level_errors/2` and reported in `file_level_errors`.

  Any *unexpected* error raised deeper in the pipeline (arbitrary input can be anything)
  is caught as a last-resort safety net and folded into `file_level_errors`, prefixed with
  `#{@unexpected_error_prefix}` so the report can later tell these apart from known,
  schema-level problems.

  On a file-level error, `valid_row_count`, `invalid_row_count`, `column_errors`, and
  `error_samples` are all `nil`/empty since there is no DataFrame to summarize from.
  """
  def validate_and_summarize(path, extension \\ ".csv") do
    body = File.read!(path)

    case Transport.IRVE.Static.Probes.file_level_errors(body, extension) do
      [] ->
        body |> validate_body() |> summarize()

      file_level_errors ->
        summary_with_file_level_errors(file_level_errors)
    end
  rescue
    error ->
      summary_with_file_level_errors([@unexpected_error_prefix <> Exception.message(error)])
  end

  defp summary_with_file_level_errors(file_level_errors) do
    %Transport.IRVE.Validator.Summary{
      valid: false,
      valid_row_count: nil,
      invalid_row_count: nil,
      total_row_count: nil,
      file_level_errors: file_level_errors,
      column_errors: %{},
      error_samples: [],
      warnings: %{},
      warning_samples: []
    }
  end

  @max_samples_per_group 5

  # Maps each warning to the raw input column (not immediately constructed from the warning name)
  @warning_value_columns %{"lon_lat_inverted" => "coordonneesXY"}

  defp summarize_warnings(df) do
    warnings = Explorer.DataFrame.select(df, &String.starts_with?(&1, "warning_"))

    warnings
    |> Explorer.DataFrame.names()
    |> Map.new(fn col -> {String.replace_prefix(col, "warning_", ""), Explorer.Series.sum(warnings[col])} end)
    |> Map.reject(fn {_name, count} -> count == 0 end)
  end

  defp warning_samples(df, warnings) do
    warnings
    |> Enum.flat_map(fn {warning_name, _count} ->
      value_col = Map.fetch!(@warning_value_columns, warning_name)

      df
      |> Explorer.DataFrame.filter_with(& &1["warning_#{warning_name}"])
      |> take_samples(value_col, :warning, warning_name)
    end)
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
      df
      |> Explorer.DataFrame.filter_with(&Explorer.Series.not(&1["check_column_#{field_name}_valid"]))
      |> take_samples(field_name, :column, field_name)
    end)
  end

  defp take_samples(df, value_col, tag_key, name) do
    df
    |> Explorer.DataFrame.select(["id_pdc_itinerance", value_col])
    |> Explorer.DataFrame.head(@max_samples_per_group)
    |> Explorer.DataFrame.to_rows()
    |> Enum.map(fn row ->
      %{:id_pdc_itinerance => row["id_pdc_itinerance"], tag_key => name, :value => row[value_col]}
    end)
  end
end
