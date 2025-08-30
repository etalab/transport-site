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

  # just a todo list, extracted from actual schema, for my implementation
  @cases_to_be_covered %{
    # Basic types
    type: "string",
    format: "email",
    type: "geopoint",
    format: "array",
    type: "integer",
    type: "number",
    type: "boolean",
    type: "date",
    format: "%Y-%m-%d",
    # Dynamic schema only
    type: "datetime",
    # End dynamic schema only

    constraints: %{
      required: false,
      required: true,
      pattern: "^\\d{9}$",
      pattern: "(?:(?:^|,)(^[A-Z]{2}[A-Z0-9]{4,33}$|Non concerné))+$",
      pattern: "^([013-9]\\d|2[AB1-9])\\d{3}$",
      pattern: "(.*?)((\\d{1,2}:\\d{2})-(\\d{1,2}:\\d{2})|24/7)",
      enum: [
        "Voirie",
        "Parking public",
        "Parking privé à usage public",
        "Parking privé réservé à la clientèle",
        "Station dédiée à la recharge rapide"
      ],
      enum: [
        "Accès libre",
        "Accès réservé"
      ],
      enum: [
        "Réservé PMR",
        "Accessible mais non réservé PMR",
        "Non accessible",
        "Accessibilité inconnue"
      ],
      enum: [
        "Direct",
        "Indirect"
      ],
      minimum: 0
    }
  }

  test "works" do
    # let's train on one of the largest files available, from the start.
    file = Path.expand("~/Downloads/qualicharge-irve-statique.csv")
    # load it, assuming only strings, so we can leverage DataFrame conveniences.
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    # use the list of fields, but load everything as string, to keep the original
    # data mostly unchanged & leave us the opportunity to run verifications on it.
    dtypes = schema["fields"] |> Enum.map(&{&1["name"], :string})

    df = Explorer.DataFrame.from_csv!(file, dtypes: dtypes)
    |> Explorer.DataFrame.select([:id_pdc_itinerance, :coordonneesXY])

    id_pdc_itinerance_pattern = get_field_by_name(schema, "id_pdc_itinerance") |> get_in(["constraints", "pattern"])
    # hardcoded & home-baked, consequence of geopoint format
    geopoint_array_pattern = ~S'^\[\-?\d+(\.\d+)?,\s?\-?\d+(\.\d+)?\]$'

    df
    |> Explorer.DataFrame.mutate(check_pattern_id_pdc_itinerance: id_pdc_itinerance |> re_contains(^id_pdc_itinerance_pattern))
    |> Explorer.DataFrame.mutate(check_format_coordonneesXY: coordonneesXY |> re_contains(^geopoint_array_pattern))
    |> IO.inspect(IEx.inspect_opts)
  end
end
