defmodule Transport.IRVE.DataFrame do
  @moduledoc """
  Tooling supporting the parsing of an IRVE static file into `Explorer.DataFrame`
  """

  @doc """
  Helper function to convert TableSchema types into DataFrame ones.

  There is no attempt to make this generic at this point, it is focusing solely
  on the static IRVE use.

  iex> Transport.IRVE.DataFrame.remap_schema_type(:geopoint)
  :string
  iex> Transport.IRVE.DataFrame.remap_schema_type(:number)
  {:u, 16}
  iex> Transport.IRVE.DataFrame.remap_schema_type(:literally_anything)
  :literally_anything
  """
  def remap_schema_type(input_type) do
    case input_type do
      :geopoint -> :string
      :number -> {:u, 16}
      type -> type
    end
  end

  @doc """
  Parse an in-memory binary of CSV content into a typed `Explorer.DataFrame` for IRVE use.

  Current behaviour is that the embedded static IRVE schema enforces the field type, for fields
  that are known.

  For instance, a `string` field in the input schema will be considered as a `string` in the `DataFrame`:

  iex> Transport.IRVE.DataFrame.dataframe_from_csv_body!("id_pdc_itinerance\\nABC123")
  #Explorer.DataFrame<
    Polars[1 x 1]
    id_pdc_itinerance string ["ABC123"]
  >

  Even if it contains something that would be considered a float (the schema type spec wins):

  iex> Transport.IRVE.DataFrame.dataframe_from_csv_body!("id_pdc_itinerance\\n22.0")
  #Explorer.DataFrame<
    Polars[1 x 1]
    id_pdc_itinerance string ["22.0"]
  >

  An `integer` field will be mapped to a `integer` (here, signed 64-bits):

  iex> Transport.IRVE.DataFrame.dataframe_from_csv_body!("nbre_pdc\\n123")
  #Explorer.DataFrame<
    Polars[1 x 1]
    nbre_pdc s64 [123]
  >

  A `boolean` field in the schema, similary, will correctly result into a `boolean` `DataFrame` field:

  iex> Transport.IRVE.DataFrame.dataframe_from_csv_body!("reservation\\nfalse")
  #Explorer.DataFrame<
    Polars[1 x 1]
    reservation boolean [false]
  >

  And dates are also handled correctly:

  iex> Transport.IRVE.DataFrame.dataframe_from_csv_body!("date_mise_en_service\\n2024-10-02")
  #Explorer.DataFrame<
    Polars[1 x 1]
    date_mise_en_service date [2024-10-02]
  >

  Other, unknown columns, are at this point kept, and types are inferred:

  iex> Transport.IRVE.DataFrame.dataframe_from_csv_body!("foo,bar\\n123,14.0")
  #Explorer.DataFrame<
    Polars[1 x 2]
    foo s64 [123]
    bar f64 [14.0]
  >

  Congratulations for reading this far.
  """
  def dataframe_from_csv_body!(body, schema \\ Transport.IRVE.StaticIRVESchema.schema_content()) do
    dtypes =
      schema
      |> Map.fetch!("fields")
      |> Enum.map(fn %{"name" => name, "type" => type} ->
        {
          String.to_atom(name),
          String.to_atom(type)
          |> Transport.IRVE.DataFrame.remap_schema_type()
        }
      end)

    Explorer.DataFrame.load_csv!(body, dtypes: dtypes)
  end
end
