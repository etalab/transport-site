defmodule Transport.IRVE.DataFrame do
  @moduledoc """
  Tooling supporting the parsing of an IRVE static file into
  an [Explorer `DataFrame`](https://hexdocs.pm/explorer/Explorer.DataFrame.html).

  This brings a number of benefits:
  - built-in data munging/preprocessing on a per-column basis
  - more efficient storage (RAM wise)
  - column typing

  See [Ten Minutes to Explorer (Livebook)](https://github.com/elixir-explorer/explorer/blob/main/notebooks/exploring_explorer.livemd)
  for a gentle introduction.
  """
  require Explorer.DataFrame

  @doc """
  Helper function to convert TableSchema types into DataFrame ones.

  There is no attempt to make this generic at this point, it is focusing solely
  on the static IRVE use.

  Only comma `,` and semicolon `;` column separators are supported. The column separator
  is inferred from the first line of the file. An exception will be raised
  if an unsupported separator is encountered.

  In strict mode (the default), the types are remapped as follow:

  iex> Transport.IRVE.DataFrame.remap_schema_type(:geopoint)
  :string
  iex> Transport.IRVE.DataFrame.remap_schema_type(:number)
  {:f, 32}
  iex> Transport.IRVE.DataFrame.remap_schema_type(:boolean)
  :boolean
  iex> Transport.IRVE.DataFrame.remap_schema_type(:literally_anything)
  :literally_anything

  In non-strict mode (used by the current prototype), we read some types as `:string`
  in order to apply clean-up before casting to the actual target type manually:

  iex> Transport.IRVE.DataFrame.remap_schema_type(:boolean, _strict = false)
  :string
  iex> Transport.IRVE.DataFrame.remap_schema_type(:literally_anything, _strict = false)
  :literally_anything
  """
  def remap_schema_type(input_type, strict \\ true)

  def remap_schema_type(input_type, true = _strict) do
    case input_type do
      :geopoint -> :string
      :number -> {:f, 32}
      type -> type
    end
  end

  def remap_schema_type(input_type, false = _strict) do
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

    delimiter = guess_delimiter!(body)

    # to be tested - do not call `load_csv!` as it will `inspect` the error
    case Explorer.DataFrame.load_csv(body, dtypes: dtypes, delimiter: delimiter) do
      {:ok, df} -> df
      {:error, error} -> raise(error)
    end
  end

  defmodule ColumnDelimiterGuessError do
    @moduledoc """
    Raised when the code could not determine the proper delimiter.

    Forwards the data that was used to make the guess, so that the caller
    can provide more insight.
    """
    defexception col_seps_frequencies: %{}

    @impl true
    def message(%{col_seps_frequencies: frequencies}) do
      "Could not guess column delimiter (frequencies: #{inspect(frequencies)})"
    end
  end

  @doc """
  Attempt to guess the column delimiter based on the provided body.

  Only `;` and `,` are allowed at this point; an exception will be thrown otherwise.

  Once the data is stripped, if only commas are remaining, this is what gets picked:

  iex> guess_delimiter!("hello,world")
  ","

  Same for semi-colons:

  iex> guess_delimiter!("hello;world;again")
  ";"

  In cases where we have mixed separators, an error is raised:

  iex> guess_delimiter!("hello;world,again")
  ** (RuntimeError) Could not guess column delimiter (frequencies: %{"," => 1, ";" => 1})

  During unit tests, bodies with a single column (hence not column separator) are allowed.
  In that case "," is assumed:

  iex> guess_delimiter!("a_single_column")
  ","

  An attempt to remove quotes, whitespaces, and UTF-8 BOM is done:

  iex> guess_delimiter!("\\uFEFF\\"hello_foobar  \\",  world, again\r")
  ","

  """
  def guess_delimiter!(body) do
    col_seps_frequencies = body |> first_line |> remove_bom() |> separators_frequencies()
    separators = Map.keys(col_seps_frequencies)

    # pattern match individually, so we can raise a proper error message
    # if we cannot determine the column separator with good certainty
    case separators do
      [";"] -> ";"
      [","] -> ","
      # for single column testing files, at this point
      [] -> ","
      # otherwise raise, but provide data for reporting
      _ -> raise ColumnDelimiterGuessError, col_seps_frequencies: col_seps_frequencies
    end
  end

  def first_line(body) do
    body
    |> String.split("\n", parts: 2)
    |> hd()
  end

  def remove_bom(string) do
    string
    |> String.replace("\uFEFF", "")
  end

  @doc """
  Remove quotes, word characters & whitespaces, then attempt to identify columns separators
  and their frequencies of appearance.

  iex> Transport.IRVE.DataFrame.separators_frequencies("hello;world;nice")
  %{";" => 2}

  iex> Transport.IRVE.DataFrame.separators_frequencies("hello,\\"world\\";nice, extra \r")
  %{";" => 1, "," => 2}
  """
  def separators_frequencies(string) do
    ~r/"|\w|\s/
    |> Regex.replace(string, "")
    |> String.graphemes()
    |> Enum.frequencies()
  end

  @doc """
  The `coordonneesXY` CSV field is provided as a JSON array (e.g. `"[47.39,0.80]"`) in the input format.

  https://schema.data.gouv.fr/etalab/schema-irve-statique/2.3.1/documentation.html#propriete-coordonneesxy

  The `preprocess_xy_coordinates` method attempts to remap that to 2 separate `x`, `y` fields, properly parsed.

  iex> Explorer.DataFrame.new([%{coordonneesXY: "[47.39,0.80]"}]) |> Transport.IRVE.DataFrame.preprocess_xy_coordinates()
  #Explorer.DataFrame<
    Polars[1 x 2]
    longitude f64 [47.39]
    latitude f64 [0.8]
  >

  We must also support cases where there are extra spaces.

  iex> Explorer.DataFrame.new([%{coordonneesXY: "[43.958037, 4.764347]"}]) |> Transport.IRVE.DataFrame.preprocess_xy_coordinates()
  #Explorer.DataFrame<
    Polars[1 x 2]
    longitude f64 [43.958037]
    latitude f64 [4.764347]
  >

  But wait, there is more. Leading and trailing spaces can also occur.

  iex> Explorer.DataFrame.new([%{coordonneesXY: " [6.128405 , 48.658737] "}]) |> Transport.IRVE.DataFrame.preprocess_xy_coordinates()
  #Explorer.DataFrame<
    Polars[1 x 2]
    longitude f64 [6.128405]
    latitude f64 [48.658737]
  >
  """
  def preprocess_xy_coordinates(df) do
    df
    |> Explorer.DataFrame.mutate(coordonneesXY: coordonneesXY |> strip("[] "))
    |> Explorer.DataFrame.mutate_with(fn df ->
      %{
        coords: Explorer.Series.split_into(df[:coordonneesXY], ",", [:longitude, :latitude])
      }
    end)
    |> Explorer.DataFrame.unnest(:coords)
    # required or we'll get `nil` values
    |> Explorer.DataFrame.mutate(longitude: longitude |> strip(" "), latitude: latitude |> strip(" "))
    |> Explorer.DataFrame.mutate_with(fn df ->
      [
        longitude: Explorer.Series.cast(df[:longitude], {:f, 64}),
        latitude: Explorer.Series.cast(df[:latitude], {:f, 64})
      ]
    end)
    |> Explorer.DataFrame.discard(:coordonneesXY)
  end

  # just what we've needed so far
  @boolean_mappings %{
    nil => nil,
    "" => nil,
    "0" => false,
    "1" => true,
    "TRUE" => true,
    "FALSE" => false,
    "false" => false,
    "true" => true,
    "False" => false,
    "True" => true,
    "VRAI" => true,
    "FAUX" => false
  }

  # experimental, I think Explorer lacks a feature to allow this operation within Polars.
  # For now, using `transform`, which is a costly operation comparatively
  # https://hexdocs.pm/explorer/Explorer.DataFrame.html#transform/3
  def preprocess_boolean(df, field_name) do
    df
    |> Explorer.DataFrame.transform([names: [field_name]], fn row ->
      %{
        (field_name <> "_remapped") => Map.fetch!(@boolean_mappings, row[field_name])
      }
    end)
    |> Explorer.DataFrame.discard(field_name)
    |> Explorer.DataFrame.rename(%{(field_name <> "_remapped") => field_name})
  end

  @doc """
  If a given column doesn't exist in the dataframe, add it & populate it
  with nil values.

  This is useful to smooth out the rare cases where optional columns are missing
  from data files.

  iex> df = Explorer.DataFrame.new(%{"id_pdc_itinerance" => ["value"]})
  iex> result = add_empty_column_if_missing(df, "tarification")
  iex> Explorer.DataFrame.to_columns(result, atom_keys: true)
  %{id_pdc_itinerance: ["value"], tarification: [nil]}

  If the column exists, don't change anything:

  iex> df = Explorer.DataFrame.new(%{"id_pdc_itinerance" => ["value"]})
  iex> result = add_empty_column_if_missing(df, "id_pdc_itinerance")
  iex> Explorer.DataFrame.to_columns(result, atom_keys: true)
  %{id_pdc_itinerance: ["value"]}
  """
  def add_empty_column_if_missing(dataframe, field_name) do
    if field_name in Explorer.DataFrame.names(dataframe) do
      dataframe
    else
      dataframe
      |> Explorer.DataFrame.mutate(%{^field_name => nil})
    end
  end
end
