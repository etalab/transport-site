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

  # @test_resources [
  #   %{
  #     # https://www.data.gouv.fr/datasets/reseau-mobive-reseau-de-recharge-publique-en-nouvelle-aquitaine/
  #     label: "Mobive (séparateur ;)",
  #     url: "https://www.data.gouv.fr/api/1/datasets/r/e90f5ccc-dbe3-41bd-8fbb-d64c27ec4e1c"
  #   }
  #   # TODO: add a latin1 case
  #   # TODO: report on non CSV data (e.g. zip, reusing the quick probe I implemented)
  #   # TODO: add a case with extraneous columns (but nothing problematic)
  #   # TODO: add a case with duplicate columns (maybe, if any)
  #   # TODO: add a case with completely broken columns
  #   # TODO: add a case with unsupported separator (e.g. `\t`)
  #   # TODO: identify more cases as handled by the raw consolidation, evaluate them, see if we need to cover them or not
  # ]

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
    @doc """
    Generate one or more rows of CSV data.
    """
    def generate_csv(row_override) do
      # the exact fields, in the exact order
      columns = Transport.IRVE.StaticIRVESchema.field_names_list()

      row_override
      |> List.wrap()
      |> Enum.map(&DB.Factory.IRVE.generate_row/1)
      |> Explorer.DataFrame.new()
      # https://github.com/elixir-explorer/explorer/issues/1126
      |> Explorer.DataFrame.select(columns)
      |> Explorer.DataFrame.dump_csv!()
    end

    def checks_for_row(key, value) do
      csv_binary = generate_csv(%{key => value})
      row_valid_name = "check_row_valid"
      column_valid_name = "check_column_#{key}_valid"
      temp_path = System.tmp_dir!() |> Path.join("irve_test_#{Ecto.UUID.generate()}.csv")
      File.write!(temp_path, csv_binary)

      try do
        temp_path
        |> Transport.IRVE.Validator.validate()
        |> Map.fetch!(:df)
        |> Explorer.DataFrame.select([row_valid_name, column_valid_name])
        |> Explorer.DataFrame.to_rows()
        |> Enum.map(fn result ->
          [
            if(result[row_valid_name] == true, do: :row_valid, else: :row_invalid),
            if(result[column_valid_name] == true, do: :column_valid, else: :column_invalid)
          ]
        end)
      after
        File.rm!(temp_path)
      end
    end

    @testcases [
      # note: for now, we do not strip heading/trailing spaces (but that will change before merge I think)
      {"siren_amenageur", "    ", :valid},
      {"siren_amenageur", "   123456789  ", :invalid},
      {"siren_amenageur", "  ABC  ", :invalid},

      # nom_amenageur
      {"nom_amenageur", "", :valid},
      {"nom_amenageur", "Société X", :valid},

      # siren_amenageur
      {"siren_amenageur", "", :valid},
      {"siren_amenageur", "123456789", :valid},
      {"siren_amenageur", "12345678", :invalid},
      {"siren_amenageur", "123A56789", :invalid},

      # contact_amenageur
      {"contact_amenageur", "", :valid},
      {"contact_amenageur", "contact@entreprise.fr", :valid},
      {"contact_amenageur", "contact@", :invalid},

      # nom_operateur
      {"nom_operateur", "", :valid},
      {"nom_operateur", "Opérateur ABC", :valid},

      # contact_operateur
      {"contact_operateur", "contact@operateur.fr", :valid},
      {"contact_operateur", "invalid@", :invalid},
      {"contact_operateur", "", :invalid},

      # telephone_operateur
      {"telephone_operateur", "", :valid},
      {"telephone_operateur", "0102030405", :valid},

      # nom_enseigne
      {"nom_enseigne", "Réseau X", :valid},
      {"nom_enseigne", "", :invalid},

      # id_station_itinerance
      {"id_station_itinerance", "FRA68P68021001", :valid},
      {"id_station_itinerance", "Non concerné", :valid},
      {"id_station_itinerance", "FRX123", :invalid},
      {"id_station_itinerance", "", :invalid},

      # id_station_local
      {"id_station_local", "", :valid},
      {"id_station_local", "01F2KMMRZVQ5FQY882PCJQAPQ0", :valid},

      # nom_station
      {"nom_station", "Station Belleville", :valid},
      {"nom_station", "", :invalid},

      # implantation_station
      {"implantation_station", "Voirie", :valid},
      {"implantation_station", "Parking public", :valid},
      {"implantation_station", "Autre", :invalid},
      {"implantation_station", "", :invalid},

      # adresse_station
      {"adresse_station", "1 avenue de la Paix 75001 Paris", :valid},
      {"adresse_station", "", :invalid},

      # code_insee_commune
      {"code_insee_commune", "", :valid},
      {"code_insee_commune", "21231", :valid},
      {"code_insee_commune", "2A031", :valid},
      {"code_insee_commune", "9900", :invalid},

      # coordonneesXY
      {"coordonneesXY", "[7.48710500,48.345345]", :valid},
      {"coordonneesXY", "[200,91]", :invalid},
      {"coordonneesXY", "", :invalid},

      # nbre_pdc
      {"nbre_pdc", "3", :valid},
      {"nbre_pdc", "0", :valid},
      {"nbre_pdc", "-1", :invalid},
      {"nbre_pdc", "3.7", :invalid},
      {"nbre_pdc", "3,7", :invalid},
      {"nbre_pdc", "", :invalid},

      # id_pdc_itinerance
      {"id_pdc_itinerance", "FRA68E680210015", :valid},
      {"id_pdc_itinerance", "Non concerné", :valid},
      {"id_pdc_itinerance", "FR12E", :invalid},
      {"id_pdc_itinerance", "", :invalid},

      # id_pdc_local
      {"id_pdc_local", "", :valid},
      {"id_pdc_local", "01F2KNFARDSJG7KEH1YHG4033M", :valid},

      # puissance_nominale
      {"puissance_nominale", "22.0", :valid},
      {"puissance_nominale", "22", :valid},
      {"puissance_nominale", "0", :valid},
      {"puissance_nominale", "-5", :invalid},
      {"puissance_nominale", "5A", :invalid},
      {"puissance_nominale", "BC", :invalid},
      {"puissance_nominale", "", :invalid},

      # prise_type_ef
      {"prise_type_ef", "true", :valid},
      {"prise_type_ef", "false", :valid},
      {"prise_type_ef", "", :invalid},

      # prise_type_2
      {"prise_type_2", "true", :valid},
      {"prise_type_2", "false", :valid},
      {"prise_type_2", "", :invalid},

      # prise_type_combo_ccs
      {"prise_type_combo_ccs", "true", :valid},
      {"prise_type_combo_ccs", "false", :valid},
      {"prise_type_combo_ccs", "", :invalid},

      # prise_type_chademo
      {"prise_type_chademo", "true", :valid},
      {"prise_type_chademo", "false", :valid},
      {"prise_type_chademo", "", :invalid},

      # prise_type_autre
      {"prise_type_autre", "true", :valid},
      {"prise_type_autre", "false", :valid},
      {"prise_type_autre", "", :invalid},

      # gratuit
      {"gratuit", "true", :valid},
      {"gratuit", "false", :valid},
      {"gratuit", "", :valid},

      # paiement_acte
      {"paiement_acte", "true", :valid},
      {"paiement_acte", "false", :valid},
      {"paiement_acte", "", :invalid},

      # paiement_cb
      {"paiement_cb", "", :valid},
      {"paiement_cb", "true", :valid},
      {"paiement_cb", "false", :valid},

      # paiement_autre
      {"paiement_autre", "", :valid},
      {"paiement_autre", "true", :valid},
      {"paiement_autre", "false", :valid},

      # tarification
      {"tarification", "", :valid},
      {"tarification", "0,40€/kWh", :valid},

      # condition_acces
      {"condition_acces", "Accès libre", :valid},
      {"condition_acces", "Accès réservé", :valid},
      {"condition_acces", "Ouvert", :invalid},
      {"condition_acces", "", :invalid},

      # reservation
      {"reservation", "true", :valid},
      {"reservation", "false", :valid},
      {"reservation", "", :invalid},

      # horaires
      {"horaires", "24/7", :valid},
      {"horaires", "Mo-Fr 08:00-18:00", :valid},
      {"horaires", "Mo-Fr 08:00-12:00,Mo-Fr 14:00-18:00,Th 08:00-18:00", :valid},
      {"horaires", "Lundi 9h-18h", :invalid},
      {"horaires", "", :invalid},

      # accessibilite_pmr
      {"accessibilite_pmr", "Réservé PMR", :valid},
      {"accessibilite_pmr", "Non accessible", :valid},
      {"accessibilite_pmr", "Autre", :invalid},
      {"accessibilite_pmr", "", :invalid},

      # restriction_gabarit
      {"restriction_gabarit", "Hauteur maximale 2m", :valid},
      {"restriction_gabarit", "", :invalid},

      # station_deux_roues
      {"station_deux_roues", "true", :valid},
      {"station_deux_roues", "false", :valid},
      {"station_deux_roues", "", :invalid},

      # raccordement
      {"raccordement", "", :valid},
      {"raccordement", "Direct", :valid},
      {"raccordement", "Indirect", :valid},
      {"raccordement", "Autre", :invalid},

      # num_pdl
      {"num_pdl", "", :valid},
      {"num_pdl", "12345678912345", :valid},

      # date_mise_en_service
      {"date_mise_en_service", "", :valid},
      {"date_mise_en_service", "2021-12-30", :valid},
      # TODO: implement support for invalid date verification, & add test-case
      {"date_mise_en_service", "30/12/2021", :invalid},

      # observations
      {"observations", "", :valid},
      {"observations", "Bornes réservées aux abonnés", :valid},

      # date_maj
      {"date_maj", "2021-12-30", :valid},
      {"date_maj", "30/12/2021", :invalid},
      # TODO: implement support for invalid date verification, & add test-case
      {"date_maj", "", :invalid},

      # cable_t2_attache
      {"cable_t2_attache", "", :valid},
      {"cable_t2_attache", "true", :valid},
      {"cable_t2_attache", "false", :valid}
    ]

    @testcases
    |> Enum.each(fn {field, value, validity} ->
      expected_result =
        case validity do
          :valid -> [:row_valid, :column_valid]
          :invalid -> [:row_invalid, :column_invalid]
        end

      @tag :focus
      test "field:#{field}(#{value |> inspect})" do
        assert checks_for_row(unquote(field), unquote(value)) == [unquote(expected_result)]
      end
    end)
  end
end
