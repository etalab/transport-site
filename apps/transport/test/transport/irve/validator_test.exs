#
# ```
# find . -name "*valid*" | entr -c mix test apps/transport/test/transport/irve/validator_test.exs --only focus
# ```
#
defmodule Transport.IRVE.ValidatorTest do
  use ExUnit.Case, async: true

  require Logger

  def compute_validation_fields(%Explorer.DataFrame{} = df, %{} = schema, validation_callback) do
    fields =
      Map.fetch!(schema, "fields")
      |> Enum.drop(2)
      |> Enum.take(1)

    Enum.reduce(fields, df, fn field, df ->
      handle_one_schema_field(df, field, validation_callback)
    end)
  end

  def handle_one_schema_field(%Explorer.DataFrame{} = df, %{} = field, validation_callback) do
    field =
      field
      |> Map.delete("description")
      |> Map.delete("example")

    # unpack the field def completely, raising on whatever remains (to protect from unhandled cases)
    {name, field} = Map.pop!(field, "name")
    {type, field} = Map.pop!(field, "type")
    {optional_format, field} = Map.pop(field, "format")
    {constraints, rest_of_field} = Map.pop!(field, "constraints")

    if rest_of_field != %{} do
      raise("Field def contains extra stuff ; please review\n#{rest_of_field |> inspect(pretty: true)}")
    end

    # at this point, the whole field definition is exploded, in full, toward specific variables, so
    # we can now work efficiently at computing validation columns for each field in the input schema
    configure_computations_for_one_schema_field(df, name, type, optional_format, constraints, validation_callback)
  end

  def configure_computations_for_one_schema_field(
        %Explorer.DataFrame{} = df,
        "nom_amenageur" = name,
        "string" = _type,
        nil = _format,
        constraints,
        _validation_callback
      ) do
    IO.puts("Configuring field checks: #{name}")

    # nothing to do - the field is always valid
    assert constraints == %{"required" => false}

    df
  end

  @test_resources [
    %{
      # https://www.data.gouv.fr/datasets/reseau-mobive-reseau-de-recharge-publique-en-nouvelle-aquitaine/
      label: "Mobive (séparateur ;)",
      url: "https://www.data.gouv.fr/api/1/datasets/r/e90f5ccc-dbe3-41bd-8fbb-d64c27ec4e1c"
    }
    # TODO: add a latin1 case
    # TODO: report on non CSV data (e.g. zip, reusing the quick probe I implemented)
    # TODO: add a case with extraneous columns (but nothing problematic)
    # TODO: add a case with duplicate columns (maybe, if any)
    # TODO: add a case with completely broken columns
    # TODO: add a case with unsupported separator (e.g. `\t`)
    # TODO: identify more cases as handled by the raw consolidation, evaluate them, see if we need to cover them or not
  ]

  @cache_dir Path.join(__DIR__, "../../cache-dir")

  def setup do
    if !File.exists?(@cache_dir), do: File.mkdir!(@cache_dir)
  end

  describe "file level validation" do
    test "reject invalid column separator"
    test "accept (with warning) semi-colon column separator"
    test "accept (with warning) latin1 encoding"
    test "reject file with extra columns"
    test "reject file with missing columns"
    test "reject file with duplicate columns"
    test "accept (with warning) incorrectly ordered columns"
  end

  describe "row level validation" do
    test "field:nom_amenageur" do
      # je construis
    end

    def generate_csv(row_override) do
      # the exact fields, in the exact order
      columns = Transport.IRVE.StaticIRVESchema.field_names_list()

      row_override
      |> DB.Factory.IRVE.generate_row()
      |> List.wrap()
      |> Explorer.DataFrame.new()
      # https://github.com/elixir-explorer/explorer/issues/1126
      |> Explorer.DataFrame.select(columns)
      |> Explorer.DataFrame.dump_csv!()
    end

    @tag :focus
    test "field:siren_amenageur" do
      # je construis un fichier avec les bonnes colonnes, avec que des lignes bonnes au départ,
      # mais N valeurs valides de SIREN aménageur, et N valeurs invalides
      # je veux qu'en sortie, je puisse compter le nombre de lignes incorrectes, le nombre de lignes
      # correctes, et avoir un message qui va bien pour la cellule de chaque ligne.

      # invalid
      csv_binary = generate_csv(%{"siren_amenageur" => "12345678"})

      csv_binary
      |> Explorer.DataFrame.load_csv!(infer_schema_length: 0)
      |> Explorer.DataFrame.select(["siren_amenageur"])
      |> IO.inspect(IEx.inspect_opts())

      temp_path = System.tmp_dir!() |> Path.join("irve_test_#{Ecto.UUID.generate()}.csv")
      File.write!(temp_path, csv_binary)

      # TO BE IMPLEMENTED
      assert Transport.IRVE.Validator.validate(temp_path) == false
    end

    test "field:contact_amenageur"
    test "field:nom_operateur"
    test "field:contact_operateur"
    test "field:telephone_operateur"
    test "field:nom_enseigne"
    test "field:id_station_itinerance"
    test "field:id_station_local"
    test "field:nom_station"
    test "field:implantation_station"
    test "field:adresse_station"
    test "field:code_insee_commune"
    test "field:coordonneesXY"
    test "field:nbre_pdc"
    test "field:id_pdc_itinerance"
    test "field:id_pdc_local"
    test "field:puissance_nominale"
    test "field:prise_type_ef"
    test "field:prise_type_2"
    test "field:prise_type_combo_ccs"
    test "field:prise_type_chademo"
    test "field:prise_type_autre"
    test "field:gratuit"
    test "field:paiement_acte"
    test "field:paiement_cb"
    test "field:paiement_autre"
    test "field:tarification"
    test "field:condition_acces"
    test "field:reservation"
    test "field:horaires"
    test "field:accessibilite_pmr"
    test "field:restriction_gabarit"
    test "field:station_deux_roues"
    test "field:raccordement"
    test "field:num_pdl"
    test "field:date_mise_en_service"
    test "field:observations"
    test "field:date_maj"
    test "field:cable_t2_attache"
  end
end
