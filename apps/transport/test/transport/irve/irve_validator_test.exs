defmodule Transport.DataFrame.TableSchemaValidator do
  @moduledoc """
  A specialized/narrow implementation of [TableSchema](https://specs.frictionlessdata.io/table-schema/)
  validator. Leverages `Explorer.DataFrame` columnar engine to achieve fast validation.
  """

  @doc """
  Define new temporary columns that will store the results of checks.

  Currently does not support missing columns (since Explorer will raise
  an error when we compute something that derives from them).
  """
  def compute_validation_fields(%Explorer.DataFrame{} = df, schema) do
    fields = Map.fetch!(schema, "fields")
    fields = fields |> Enum.take(2)

    Enum.reduce(fields, df, fn field, acc ->
      configure_field(field, df)
    end)
  end

  def configure_field(field, df) do
    field = field |> Map.delete("description") |> Map.delete("example")
    {name, field} = Map.pop!(field, "name")
    type = Map.fetch!(field, "type")
    constraints = Map.fetch!(field, "constraints")

    cond do
      constraints == %{"required" => false} && type == "string" ->
        # do nothing, easy
        df

      true ->
        raise "Field definition uses unsupported scenarios (#{name})\n#{field |> inspect(pretty: true, width: 0)}"
    end
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

    Transport.DataFrame.TableSchemaValidator.compute_validation_fields(df, schema)
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
