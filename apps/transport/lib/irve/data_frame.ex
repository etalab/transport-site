defmodule Transport.IRVE.DataFrame do
  @moduledoc """
  Tooling supporting the parsing of an IRVE static file into `Explorer.DataFrame`
  """
  require Explorer.DataFrame

  @doc """
  Helper function to convert TableSchema types into DataFrame ones.

  There is no attempt to make this generic at this point, it is focusing solely
  on the static IRVE use.

  iex> Transport.IRVE.DataFrame.remap_schema_type(:geopoint)
  :string
  iex> Transport.IRVE.DataFrame.remap_schema_type(:number)
  {:f, 32}
  iex> Transport.IRVE.DataFrame.remap_schema_type(:literally_anything)
  :literally_anything
  """
  def remap_schema_type(input_type, strict \\ true)

  def remap_schema_type(input_type, true) do
    case input_type do
      :geopoint -> :string
      :number -> {:f, 32}
      type -> type
    end
  end

  def remap_schema_type(input_type, false) do
    case remap_schema_type(input_type, true) do
      :boolean -> :string
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
  def dataframe_from_csv_body!(body, schema \\ Transport.IRVE.StaticIRVESchema.schema_content(), strict \\ true) do
    dtypes =
      schema
      |> Map.fetch!("fields")
      |> Enum.map(fn %{"name" => name, "type" => type} ->
        {
          String.to_atom(name),
          String.to_atom(type)
          |> Transport.IRVE.DataFrame.remap_schema_type(strict)
        }
      end)

    # to be tested - do not call `load_csv!` as it will `inspect` the error
    case Explorer.DataFrame.load_csv(body, dtypes: dtypes) do
      {:ok, df} -> df
      {:error, error} -> raise(error)
    end
  end

  @doc """
  iex> Explorer.DataFrame.new([%{coordonneesXY: "[47.39,0.80]"}]) |> Transport.IRVE.DataFrame.preprocess_data()
  #Explorer.DataFrame<
    Polars[1 x 2]
    x f64 [47.39]
    y f64 [0.8]
  >

  We must also support cases where there are extra spaces.

  iex> Explorer.DataFrame.new([%{coordonneesXY: "[43.958037, 4.764347]"}]) |> Transport.IRVE.DataFrame.preprocess_data()
  #Explorer.DataFrame<
    Polars[1 x 2]
    x f64 [43.958037]
    y f64 [4.764347]
  >

  But wait, there is more. Leading and trailing spaces can also occur.

  iex> Explorer.DataFrame.new([%{coordonneesXY: " [6.128405 , 48.658737] "}]) |> Transport.IRVE.DataFrame.preprocess_data()
  #Explorer.DataFrame<
    Polars[1 x 2]
    x f64 [6.128405]
    y f64 [48.658737]
  >
  """
  def preprocess_data(df) do
    df
    |> Explorer.DataFrame.mutate(coordonneesXY: coordonneesXY |> strip("[] "))
    |> Explorer.DataFrame.mutate_with(fn df ->
      %{
        coords: Explorer.Series.split_into(df[:coordonneesXY], ",", [:x, :y])
      }
    end)
    |> Explorer.DataFrame.unnest(:coords)
    # required or we'll get `nil` values
    |> Explorer.DataFrame.mutate(x: x |> strip(" "))
    |> Explorer.DataFrame.mutate(y: y |> strip(" "))
    |> Explorer.DataFrame.mutate_with(fn df ->
      [
        x: Explorer.Series.cast(df[:x], {:f, 64}),
        y: Explorer.Series.cast(df[:y], {:f, 64})
      ]
    end)
    |> Explorer.DataFrame.discard(:coordonneesXY)
  end
end
