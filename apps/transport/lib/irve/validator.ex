defmodule Transport.IRVE.Validator do
  require Logger

  alias Transport.IRVE.Validator.FieldValidation

  @moduledoc """
  This modules implements a validator for the static IRVE file format (see `schema-irve-statique.json`).

  It aims to comply with:
  - a subset of the `TableSchema` specification https://specs.frictionlessdata.io/table-schema/
  - and for only the static IRVE schema at this point
  """

  def validate(file_path) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    callback = fn
      # an error is blocking - we just exit right away
      {:fatal_error, _error_type, _error_details} = event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
        throw(:fatal_validation_error)

      {:info, _msg} = event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
    end

    try do
      Logger.info("Validating IRVE static file at #{file_path}")
      delimiter = guess_supported_column_separator!(file_path, callback)
      df = load_dataframe!(file_path, delimiter)
      verify_columns!(df, schema, callback)
      # at this point we should have exactly the columns required
      df = preprocess_data(df)
      df = setup_column_checks(df, schema)
      df = setup_row_check(df)

      stats = compute_row_validity_stats(df)

      %{
        # provide an aggregate
        file_valid: stats.row_invalid_count == 0,
        # help me during tests for now
        row_stats: stats,
        df: df
      }
    catch
      :fatal_validation_error ->
        # TODO: bubble up the exact reason, since the file was not processed
        %{
          file_valid: false
        }
    end
  end

  @doc """
  Compute row stats (number of valid / invalid / total row count)
  """
  def compute_row_validity_stats(%Explorer.DataFrame{} = df, column_name \\ "check_row_valid") do
    values =
      df
      |> Explorer.DataFrame.frequencies([column_name])
      |> Explorer.DataFrame.to_rows()

    f = fn c_name, bool ->
      values
      |> Enum.find(%{"counts" => 0}, &(&1[c_name] == bool))
      |> Map.fetch!("counts")
    end

    result = %{
      row_valid_count: a = f.(column_name, true),
      row_invalid_count: b = f.(column_name, false)
    }

    Map.put(result, :row_total_count, a + b)
  end

  def guess_supported_column_separator!(file_path, validation_callback) do
    [file_first_line] =
      File.stream!(file_path)
      |> Enum.take(1)

    # determine if we have an acceptable delimiter, or not
    delimiter =
      try do
        Transport.IRVE.DataFrame.guess_delimiter!(file_first_line)
      rescue
        e in Transport.IRVE.DataFrame.ColumnDelimiterGuessError ->
          validation_callback.({:fatal_error, :unsupported_delimiter, e})
      end

    # only "," and ";" are supported. othercases will normally raise above, or
    # worst case result in `case` failure here
    case delimiter do
      "," ->
        # best case - no warnings, we're good, do nothing!
        true

      ";" ->
        # we're accepting it, but that's not what is normally expected, signal it
        validation_callback.({:warning, :delimiter_correction_applied, delimiter})
    end

    delimiter
  end

  def load_dataframe!(file_path, delimiter) do
    # https://hexdocs.pm/explorer/Explorer.html#from_csv/2-options
    options = [
      # set to zero disables inference and default all values to string.
      # this is what we want to keep the input intact & be able to report on its (in)validity
      # "(set to) zero to disable inference and default all values to string"
      infer_schema_length: 0,
      delimiter: delimiter
    ]

    Explorer.DataFrame.from_csv!(file_path, options)
  end

  @doc """
  Preprocess the dataframe before validation:
  - Strip leading/trailing whitespace from all string columns
  """
  def preprocess_data(%Explorer.DataFrame{} = df) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      df
      |> Explorer.DataFrame.names()
      |> Enum.map(fn col_name ->
        series = Explorer.Series.strip(df[col_name])
        {col_name, series}
      end)
      |> Map.new()
    end)
  end

  def verify_columns!(%Explorer.DataFrame{} = df, schema, validation_callback) do
    schema_columns = Transport.IRVE.StaticIRVESchema.field_names_list(schema)
    columns = Explorer.DataFrame.names(df)
    # exact comparison (MUST in the spec), in the exact same order
    if columns != schema_columns do
      # NOTE: this could lead to a non-blocking warning (such as "we have extra columns, this is not recommended, but we'll take your file for now")
      # or to harder stuff (e.g. "you have duplicates, please fix this, we won't go forward")
      validation_callback.({:fatal_error, :invalid_columns, "TO BE SPECIFIED & SPLIT IN SEPARATE CASES"})
    end
  end

  def setup_column_checks(%Explorer.DataFrame{} = df, schema) do
    schema
    |> Map.fetch!("fields")
    |> Enum.reduce(df, fn field_definition, df ->
      # mandatory
      field_name = field_definition |> Map.fetch!("name")
      field_type = field_definition |> Map.fetch!("type")
      field_constraints = field_definition |> Map.fetch!("constraints")
      # optional
      field_format = field_definition["format"]

      # TODO: assert that nothing is left in the def

      # Process all fields - no filtering
      configure_computations_for_one_schema_field(df, field_name, field_type, field_format, field_constraints)
    end)
  end

  @doc """
  Grab all the `check_column_xyz` fields, and build a `and` operation between all of them.
  """
  def setup_row_check(%Explorer.DataFrame{} = df) do
    df
    |> Explorer.DataFrame.mutate_with(fn df ->
      row_valid =
        df
        |> Explorer.DataFrame.names()
        |> Enum.filter(&String.starts_with?(&1, "check_column_"))
        |> Enum.map(&df[&1])
        |> Enum.reduce(&Explorer.Series.and/2)

      %{"check_row_valid" => row_valid}
    end)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        field_name,
        type,
        format,
        constraints
      ) do
    {required, validation_constraints} = Map.pop!(constraints, "required")

    Explorer.DataFrame.mutate_with(df, fn df ->
      base_validation = FieldValidation.perform_base_validation(df, field_name, type, format, validation_constraints)
      final_validation = FieldValidation.apply_optionality(df[field_name], base_validation, required)

      %{"check_column_#{field_name}_valid" => final_validation}
    end)
  end
end
