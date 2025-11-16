defmodule Transport.DataFrame.Validation.DataFrameValidationTest do
  use ExUnit.Case, async: true

  # all the test-cases, assuming the data has been trimmed from
  # leading & trailing whitespaces.
  @test_cases [
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
    # TODO: open issue, the schema currently allows this and this is way to lax
    {"id_station_itinerance", "FRX123", :valid},
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
    {"coordonneesXY", "[-7.123,-23.678]", :valid},
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
    {"date_mise_en_service", "2020-02-29", :valid},
    {"date_mise_en_service", "2024-02-30", :invalid},
    {"date_mise_en_service", "30/12/2021", :invalid},

    # observations
    {"observations", "", :valid},
    {"observations", "Bornes réservées aux abonnés", :valid},

    # date_maj
    {"date_maj", "2021-12-30", :valid},
    {"date_maj", "2024-02-30", :invalid},
    {"date_maj", "30/12/2021", :invalid},
    {"date_maj", "", :invalid},

    # cable_t2_attache
    {"cable_t2_attache", "", :valid},
    {"cable_t2_attache", "true", :valid},
    {"cable_t2_attache", "false", :valid}
  ]

  def to_boolean(:valid), do: true
  def to_boolean(:invalid), do: false

  @test_cases
  |> Enum.each(fn {field, value, validity} ->
    test "field:#{field}(#{value |> inspect})" do
      validity = to_boolean(unquote(validity))

      assert compute_validity(unquote(field), unquote(value)) == [
               [row_valid: validity, column_valid: validity]
             ]
    end
  end)

  def stringify_row(row), do: row |> Enum.map(fn {a, b} -> {a, b |> to_string} end)

  test "default factory IRVE row is considered valid" do
    row =
      DB.Factory.IRVE.generate_row()
      |> stringify_row()

    [result] =
      [row]
      |> compute_validity()
      |> Explorer.DataFrame.select(~r/\Acheck/)
      |> Explorer.DataFrame.to_rows()

    expected_result =
      Transport.IRVE.StaticIRVESchema.field_names_list()
      |> Enum.map(fn f -> {"check_column_#{f}_valid", true} end)
      |> Enum.into(%{"check_row_valid" => true})

    assert result == expected_result
  end

  @doc """
  Check how forcing a specific IRVE field to a given value affects validity.

  A valid baseline row is generated, the `field` is overridden, and the
  DataFrame validators run.

  Returns: [%{row_valid: boolean(), column_valid: boolean()}]
  """
  def compute_validity(field, value) do
    row =
      %{field => value}
      |> DB.Factory.IRVE.generate_row()
      |> stringify_row()

    row_valid_name = "check_row_valid"
    column_valid_name = "check_column_#{field}_valid"

    compute_validity([row])
    |> Explorer.DataFrame.select([row_valid_name, column_valid_name])
    |> Explorer.DataFrame.to_rows()
    |> Enum.map(fn row ->
      [row_valid: row[row_valid_name], column_valid: row[column_valid_name]]
    end)
  end

  def compute_validity(rows) do
    schema = Transport.IRVE.StaticIRVESchema.schema_content()

    rows
    |> Explorer.DataFrame.new()
    |> Transport.IRVE.Validator.DataFrameValidation.setup_field_validation_columns(schema)
    |> Transport.IRVE.Validator.DataFrameValidation.setup_row_check()
  end
end
