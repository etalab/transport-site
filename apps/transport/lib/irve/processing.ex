defmodule Transport.IRVE.Processing do
  @moduledoc """
  Leverages `Transport.IRVE.DataFrame` (see more doc there) and `Explorer.DataFrame` to read
  and preprocess (to some extent) a raw CSV binary body.
  """

  @doc """
  Takes a CSV body, read it as `DataFrame`, then preprocess all the required fields.
  """
  def read_as_data_frame(body) do
    body
    |> convert_to_dataframe!()
    |> add_missing_optional_columns()
    |> preprocess_coordinates()
    |> Transport.IRVE.CoordinateCorrection.detect_and_correct()
    |> preprocess_boolean_fields()
    |> select_fields()
  end

  @doc """
  Same as above, but prepares the DataFrame without any type casting, all columns remain strings.
  This is useful for validation purposes.
  """
  def read_as_uncasted_data_frame(body) do
    body
    # This allows non-comma delimiters, should have a warning accumulation later
    |> convert_to_uncasted_dataframe!()
    # Same as above, should exit a warning accumulation later
    |> add_missing_optional_columns(true)
    # True means: keep as string, avoid type interpolation
    |> preprocess_boolean_fields(true)

    # TODO: take care of field / column selection
  end

  @doc """
  Casts an uncasted (all-strings) DataFrame — the output of `read_as_uncasted_data_frame/1`,
  possibly enriched with validation columns — to the same typed, insert-ready shape as
  `read_as_data_frame/1`, without re-parsing the CSV.

  Only fully-valid frames are expected here (whole-file gate): every value is castable by
  construction. A cast failure means the validator and this cast disagree, which is a bug —
  we let it raise.
  """
  def cast_validated_frame(dataframe) do
    dataframe
    |> cast_to_schema_dtypes()
    |> preprocess_coordinates()
    |> Transport.IRVE.CoordinateCorrection.detect_and_correct()
    |> select_fields()
  end

  # The uncasted path materializes missing values as `""` (see `keep_as_string` variants above),
  # while the typed parse produces `nil` — so normalize before casting.
  defp cast_to_schema_dtypes(dataframe) do
    Transport.IRVE.DataFrame.schema_dtypes()
    |> Enum.reduce(dataframe, fn {column, dtype}, df_acc ->
      series =
        df_acc[Atom.to_string(column)]
        # TODO: fix casting / validator to avoid recreating nil values from empty strings
        |> empty_strings_as_nil()
        |> cast_series(dtype)

      Explorer.DataFrame.put(df_acc, column, series)
    end)
  end

  @doc """
  Replaces empty strings (`""`) with `nil` in a string series, leaving every other value
  (including existing `nil`s) untouched.

  iex> Explorer.Series.from_list(["hello", "", nil, "world"]) |> empty_strings_as_nil() |> Explorer.Series.to_list()
  ["hello", nil, nil, "world"]
  """
  def empty_strings_as_nil(series) do
    # `equal` yields nil for nil cells so we fill nills with false
    is_an_empty_string = series |> Explorer.Series.equal("") |> Explorer.Series.fill_missing(false)
    nil_string = Explorer.Series.from_list([nil], dtype: :string)
    Explorer.Series.select(is_an_empty_string, nil_string, series)
  end

  @doc """
  Casts a string series to the given dtype.
  Polars does not support casting strings to booleans, so we implement it manually here.

  iex> Explorer.Series.from_list(["true", "false", nil]) |> cast_series(:boolean) |> Explorer.Series.to_list()
  [true, false, nil]
  """
  def cast_series(series, :boolean), do: Explorer.Series.equal(series, "true")
  def cast_series(series, dtype), do: Explorer.Series.cast(series, dtype)

  def convert_to_dataframe!(body) do
    # TODO: be smooth about `cable_t2_attache` - only added in v2.1.0 (https://github.com/etalab/schema-irve/releases/tag/v2.1.0)
    # and often not provided
    body
    |> Transport.IRVE.DataFrame.dataframe_from_csv_body!(
      Transport.IRVE.StaticIRVESchema.schema_content(),
      # NOTE: we read as non-strict (impacts booleans at time of writing)
      # because we manually reprocess them right here after.
      _strict = false
    )
  end

  defp convert_to_uncasted_dataframe!(body) do
    delimiter = Transport.IRVE.DataFrame.guess_delimiter!(body)
    # TODO: accumulate warning
    # NOTE: `infer_schema_length: 0` enforces strings everywhere
    case Explorer.DataFrame.load_csv(body, infer_schema_length: 0, delimiter: delimiter) do
      {:ok, df} -> df
      {:error, error} -> raise "Error loading CSV into dataframe: #{inspect(error)}"
    end
  end

  def preprocess_coordinates(dataframe) do
    Transport.IRVE.DataFrame.preprocess_xy_coordinates(dataframe)
  end

  def preprocess_boolean_fields(dataframe, keep_as_string \\ false) do
    Transport.IRVE.StaticIRVESchema.boolean_columns()
    |> Enum.reduce(dataframe, fn column, dataframe_acc ->
      Transport.IRVE.DataFrame.preprocess_boolean(dataframe_acc, column, keep_as_string)
    end)
  end

  @doc """
  Add empty columns for optional schema fields that are sometimes missing in CSV files.

  Manually cherry-picked fields which are all "non-required" in the schema at time of writing.

  A later version will likely automatically use all fields, but manual exceptions are likely
  to still be useful.

  Note: the field `cable_t2_attache` is added here, and then in the "raw static consolidation"
  path it is later removed again in `select_fields/1`.
  """
  def add_missing_optional_columns(dataframe, keep_as_string \\ false) do
    Transport.IRVE.StaticIRVESchema.optional_fields()
    |> Enum.reduce(dataframe, fn column, dataframe_acc ->
      Transport.IRVE.DataFrame.add_empty_column_if_missing(dataframe_acc, column, keep_as_string)
    end)
  end

  def select_fields(dataframe) do
    dataframe
    |> Explorer.DataFrame.select(
      (Transport.IRVE.StaticIRVESchema.field_names_list() --
         ["coordonneesXY", "cable_t2_attache"]) ++
        ["longitude", "latitude", "consolidated_is_lon_lat_correct"]
    )
  end
end
