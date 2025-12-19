defmodule Transport.DataFrame.Validation.DataFrameValidationTest do
  # all the test-cases, assuming the data has been trimmed from
  # leading & trailing whitespaces.
  @test_cases [
    # first, verify that full row validation with a special tuple.
    {:full_default_factory_row, :valid},

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

  use ExUnit.Case,
    async: true,
    parameterize: Enum.map(@test_cases, &%{test_data: &1})

  test "validation", %{test_data: test_data} do
    test_the_validation(test_data)
  end

  # full row version - test the validation on the default factory row
  defp test_the_validation({:full_default_factory_row, :valid}) do
    row = DB.Factory.IRVE.generate_row() |> stringify_row()
    result = run_dataframe_validators([row])
    assert result["check_row_valid"] |> Explorer.Series.to_list() == [true]
    assert result |> Transport.IRVE.Validator.full_file_valid?()
  end

  # "single field changed from the default factory row" version
  defp test_the_validation({field, value, validity}) do
    row = %{field => value} |> DB.Factory.IRVE.generate_row() |> stringify_row()

    row_valid_name = "check_row_valid"
    column_valid_name = "check_column_#{field}_valid"

    result =
      [row]
      |> run_dataframe_validators()
      |> Explorer.DataFrame.select([row_valid_name, column_valid_name])
      |> Explorer.DataFrame.to_rows()

    validity = to_boolean(validity)

    assert result == [%{row_valid_name => validity, column_valid_name => validity}]
  end

  defp to_boolean(:valid), do: true
  defp to_boolean(:invalid), do: false

  defp stringify_row(row), do: row |> Enum.map(fn {a, b} -> {a, b |> to_string} end)

  defp run_dataframe_validators(rows) do
    Transport.IRVE.Validator.compute_validation(rows |> Explorer.DataFrame.new())
  end
end
