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

  def preprocess_coordinates(dataframe) do
    Transport.IRVE.DataFrame.preprocess_xy_coordinates(dataframe)
  end

  def preprocess_boolean_fields(dataframe) do
    (Transport.IRVE.StaticIRVESchema.boolean_columns() -- ["cable_t2_attache"])
    |> Enum.reduce(dataframe, fn column, dataframe_acc ->
      Transport.IRVE.DataFrame.preprocess_boolean(dataframe_acc, column)
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
