defmodule Transport.IRVE.Validator do
  require Logger

  @moduledoc """
  This modules implements a validator for the static IRVE file format (see `schema-irve-statique.json`).

  It aims to comply with:
  - a subset of the `TableSchema` specification https://specs.frictionlessdata.io/table-schema/
  - and for only the static IRVE schema at this point
  """

  def validate(file_path) do
    schema_columns = Transport.IRVE.StaticIRVESchema.field_names_list()

    callback = fn
      # an error is blocking - we just exit right away
      {:fatal_error, error_type, error_details} = event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
        throw :fatal_validation_error
      {:info, msg} = event ->
        IO.inspect(event, IEx.inspect_opts() |> Keyword.put(:label, "Event"))
    end

    try do
      Logger.info("Validating IRVE static file at #{file_path}")
      delimiter = guess_supported_column_separator!(file_path, callback)
      df = load_dataframe!(file_path, delimiter, callback)
      verify_columns!(df, schema_columns, callback)
      # at this point we should have exactly the columns required
      true
    catch
      :fatal_validation_error -> false
    end
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

  def load_dataframe!(file_path, delimiter, validation_callback) do
    # https://hexdocs.pm/explorer/Explorer.DataFrame.html#from_csv/2-options
    options = [
      # set to zero disables inference and default all values to string.
      # this is what we want to keep the input intact & be able to report on its (in)validity
      # "(set to) zero to disable inference and default all values to string"
      infer_schema_length: 0,
      delimiter: delimiter
    ]
    Explorer.DataFrame.from_csv!(file_path, options)
  end

  def verify_columns!(%Explorer.DataFrame{} = df, schema_columns, validation_callback) do
    columns = Explorer.DataFrame.names(df)
    # exact comparison (MUST in the spec), in the exact same order
    if columns != schema_columns do
      # NOTE: this could lead to a non-blocking warning (such as "we have extra columns, this is not recommended, but we'll take your file for now")
      # or to harder stuff (e.g. "you have duplicates, please fix this, we won't go forward")
      validation_callback.({:error, :invalid_columns, "TO BE SPECIFIED & SPLIT IN SEPARATE CASES"})
    else
      validation_callback.({:info, :columns_are_valid_yay})
      validation_callback.({:info, :file_is_valid_at_this_point})
    end
  end
end
