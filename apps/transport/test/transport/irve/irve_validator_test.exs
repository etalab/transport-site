defmodule Transport.DataFrame.TableSchemaValidator do
  @moduledoc """
  A specialized/narrow implementation of [TableSchema](https://specs.frictionlessdata.io/table-schema/)
  validator. Leverages `Explorer.DataFrame` columnar engine to achieve fast validation.

  Constraints: see https://specs.frictionlessdata.io/table-schema/#constraints
  """

  @doc """
  Define new temporary columns that will store the results of checks.

  Currently does not support missing columns (since Explorer will raise
  an error when we compute something that derives from them).
  """
  def compute_validation_fields(%Explorer.DataFrame{} = df, schema) do
    fields = Map.fetch!(schema, "fields")
    fields = fields |> Enum.take(15)

    Enum.reduce(fields, df, fn field, df ->
      configure_field(field, df)
    end)
  end

  def configure_field(field, df) do
    field =
      field
      |> Map.delete("description")
      |> Map.delete("example")

    {name, field} = Map.pop!(field, "name")
    {type, field} = Map.pop!(field, "type")
    {optional_format, field} = Map.pop(field, "format")
    IO.inspect("Configuring field #{name}:#{type}")
    {constraints, rest_of_field} = Map.pop!(field, "constraints")
    # ensure that there is nothing left that we do not support yet
    if rest_of_field != %{},
      do: raise("Field def contains extra stuff ; please review\n#{rest_of_field |> inspect(pretty: true)}")

    # configure all constraints
    df =
      Enum.reduce(constraints, df, fn constraint, df ->
        configure_field_constraint(df, name, type, constraint)
      end)

    # configure the optional format
    if optional_format, do: configure_field_constraint(df, name, type, {"format", optional_format}), else: df
  end

  def configure_field_constraint(df, name, type, {"required", false} = constraint) do
    df
  end

  # TODO: add unit tests for "", "   " etc
  # NOTE: current Polars configuration already mutates "" to nil, before that step
  def configure_field_constraint(df, name, "string", {"required", true} = constraint) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      %{"check_required_#{name}" => Explorer.Series.is_not_nil(df[name])}
    end)
  end

  def configure_field_constraint(df, name, "string", {"pattern", pattern}) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      %{"check_pattern_#{name}" => Explorer.Series.re_contains(df[name], pattern)}
    end)
  end

  # A very simple, yet likely to create false negatives, regexp to validate email addresses
  # to be improved if we see false negatives ; no need to bring in the full regex monster there
  # given the panel of addresses that we are likely to validate.
  # See https://docs.rs/regex/latest/regex/ for modifiers & precise syntax
  #
  # NOTE: this is _not_ an Elixir regex, but a string containing a pattern compiled
  # to a regex by Explorer/the Polars crate
  @simple_email_pattern ~S/(?i)\A^[\w+\.\-]+@[\w+\.\-]+\z/

  def configure_field_constraint(df, name, "string", {"format", "email"}) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      %{"check_format_#{name}" => Explorer.Series.re_contains(df[name], @simple_email_pattern)}
    end)
  end

  def configure_field_constraint(df, name, "string", {"enum", enum_values}) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      %{"check_enum_#{name}" => Explorer.Series.in(df[name], enum_values)}
    end)
  end

  # hardcoded & home-baked, consequence of geopoint format
  @geopoint_array_pattern ~S'\A\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]\z'

  def configure_field_constraint(df, name, "geopoint", {"required", true}) do
  # NOTE: the requirement aspect is indirectly already covered by the geopoint format array check below
    df
  end

  # `array` is the only supported `geopoint` format in this implementation.
  def configure_field_constraint(df, name, "geopoint", {"format", "array"}) do
    Explorer.DataFrame.mutate_with(df, fn df ->
      %{"check_geopoint_#{name}" => df[name] |> Explorer.Series.re_contains(@geopoint_array_pattern)}
    end)
  end
end

defmodule Transport.IRVE.ValidationTests do
  use ExUnit.Case, async: true
  doctest Transport.IRVE.Validator, import: true

  import Explorer.Series
  import Explorer.DataFrame

  def test_df do
    Explorer.DataFrame.new(id_pdc_itinerance: ["FR55CE062704364129771300611", "FR55CE063804387840874482971", "POK"])
  end

  def get_field_by_name(schema, field_name) do
    [field] = schema["fields"] |> Enum.filter(fn x -> x["name"] == field_name end)
    field
  end

  test "validator" do
    # let's train on one of the largest files available, from the start.
    file = Path.expand("~/Downloads/qualicharge-irve-statique.csv")
    schema = Transport.IRVE.StaticIRVESchema.schema_content()
    # TODO: allow missing fields, but with a proper warning
    dtypes = schema["fields"] |> Enum.map(&{&1["name"], :string})
    df = Explorer.DataFrame.from_csv!(file, dtypes: dtypes)

    df = Transport.DataFrame.TableSchemaValidator.compute_validation_fields(df, schema)

    df
    |> Explorer.DataFrame.select(~r/\Acheck_/)
    |> IO.inspect(IEx.inspect_opts())
  end

  @tag :skip
  test "works" do
    # let's train on one of the largest files available, from the start.
    file = Path.expand("~/Downloads/qualicharge-irve-statique.csv")
    # load it, assuming only strings, so we can leverage DataFrame conveniences.
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    # use the list of fields, but load everything as string, to keep the original
    # data mostly unchanged & leave us the opportunity to run verifications on it.
    dtypes = schema["fields"] |> Enum.map(&{&1["name"], :string})

    df =
      Explorer.DataFrame.from_csv!(file, dtypes: dtypes)
      |> Explorer.DataFrame.select([
        :id_pdc_itinerance,
        :contact_amenageur,
        :coordonneesXY,
        :implantation_station
      ])

    id_pdc_itinerance_pattern = get_field_by_name(schema, "id_pdc_itinerance") |> get_in(["constraints", "pattern"])
    # hardcoded & home-baked, consequence of geopoint format
    geopoint_array_pattern = ~S'^\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]$'

    enum_values =
      get_field_by_name(schema, "implantation_station")
      |> get_in(["constraints", "enum"])
      |> Explorer.Series.from_list()

    # https://specs.frictionlessdata.io/table-schema/#types-and-formats

    # Current status: profiling the static schema (see @cases_to_be_covered),
    # gradually adding more families of checks (one concrete case per type of check).
    df =
      df
      |> Explorer.DataFrame.mutate(
        check_pattern_id_pdc_itinerance: id_pdc_itinerance |> re_contains(^id_pdc_itinerance_pattern)
      )
      |> Explorer.DataFrame.mutate(check_format_coordonneesXY: coordonneesXY |> re_contains(^geopoint_array_pattern))
      |> Explorer.DataFrame.mutate(
        check_enum_implantation_station: Explorer.Series.in(implantation_station, ^enum_values)
      )
      # TODO: replace by proper email regexp, this is quick boilerplate for now
      |> Explorer.DataFrame.mutate(check_email_contact_amenageur: contact_amenageur |> re_contains(~S/\A.*@.*\z/))

    # compute overall validity of the row, taking all the checks into account
    df =
      df
      |> Explorer.DataFrame.mutate_with(fn df ->
        # grab all the `check_` fields, and build a `and` operation between all of them
        row_valid =
          df
          |> Explorer.DataFrame.names()
          |> Enum.filter(&String.starts_with?(&1, "check_"))
          |> Enum.map(&df[&1])
          |> Enum.reduce(&Explorer.Series.and/2)

        [row_valid: row_valid]
      end)
      |> IO.inspect(IEx.inspect_opts())
  end
end
