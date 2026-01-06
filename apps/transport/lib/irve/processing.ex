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
    |> preprocess_boolean_fields()
    |> select_fields()
  end

  @doc """
  Same as above, but prepares the DataFrame without any type casting, all columns remain strings.
  This is useful for validation purposes.
  """

  def read_as_uncasted_data_frame(body) do
    # In raw static consolidation we use the following lines:
    #  body
    # |> convert_to_dataframe!() => can’t use it here, because it interpolates types from the schema
    # |> add_missing_optional_columns() => This one is kept, see below
    # |> preprocess_coordinates() => the validator already does something similar later
    # |> preprocess_boolean_fields() => this is kept but with a flag to avoid type interpolation
    # |> select_fields() => this one removes too much columns for "raw"

    body
    # This allows non-comma delimiters, should have a warning accumulation later
    |> convert_to_uncasted_dataframe!()
    # Same as above, should exit a warning accumulation later
    |> add_missing_optional_columns()
    # True means: keep as string, avoid type interpolation
    |> preprocess_boolean_fields(true)
  end

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
  def add_missing_optional_columns(dataframe) do
    Transport.IRVE.StaticIRVESchema.optional_fields()
    |> Enum.reduce(dataframe, fn column, dataframe_acc ->
      Transport.IRVE.DataFrame.add_empty_column_if_missing(dataframe_acc, column)
    end)
  end

  def select_fields(dataframe) do
    dataframe
    |> Explorer.DataFrame.select(
      (Transport.IRVE.StaticIRVESchema.field_names_list() --
         ["coordonneesXY", "cable_t2_attache"]) ++
        ["longitude", "latitude"]
    )
  end
end
