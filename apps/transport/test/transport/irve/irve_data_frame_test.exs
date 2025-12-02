defmodule Transport.IRVE.DataFrameTest do
  use ExUnit.Case, async: true
  doctest Transport.IRVE.DataFrame, import: true

  test "schema content" do
    data =
      Transport.IRVE.StaticIRVESchema.schema_content()
      |> Map.fetch!("fields")
      |> Enum.at(0)
      |> Map.take(["name", "type"])

    assert data == %{"name" => "nom_amenageur", "type" => "string"}
  end

  test "dataframe roundtrip (encode + decode)" do
    body = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()
    df = Transport.IRVE.DataFrame.dataframe_from_csv_body!(body)
    maps = Explorer.DataFrame.to_rows(df)

    assert maps == [
             %{
               "nom_amenageur" => "Métropole de Nulle Part",
               "siren_amenageur" => "123456782",
               "contact_amenageur" => "amenageur@example.com",
               "nom_operateur" => "Opérateur de Charge",
               "contact_operateur" => "operateur@example.com",
               "telephone_operateur" => "0199456782",
               "nom_enseigne" => "Réseau de recharge",
               "id_station_itinerance" => "FRPAN99P12345678",
               "id_station_local" => "station_001",
               "nom_station" => "Ma Station",
               "implantation_station" => "Voirie",
               "adresse_station" => "26 rue des écluses, 17430 Champdolent",
               "code_insee_commune" => "17085",
               "coordonneesXY" => "[-0.799141,45.91914]",
               "nbre_pdc" => 1,
               "id_pdc_itinerance" => "FRPAN99E12345678",
               "id_pdc_local" => "pdc_001",
               "puissance_nominale" => 22,
               "prise_type_ef" => false,
               "prise_type_2" => true,
               "prise_type_combo_ccs" => false,
               "prise_type_chademo" => false,
               "prise_type_autre" => false,
               "gratuit" => false,
               "paiement_acte" => true,
               "paiement_cb" => true,
               "paiement_autre" => true,
               "tarification" => "2,50€ / 30min puis 0,025€ / minute",
               "condition_acces" => "Accès libre",
               "reservation" => false,
               "horaires" => "24/7",
               "accessibilite_pmr" => "Accessible mais non réservé PMR",
               "restriction_gabarit" => "Hauteur maximale 2.30m",
               "station_deux_roues" => false,
               "raccordement" => "Direct",
               "num_pdl" => "12345678912345",
               "date_mise_en_service" => ~D[2024-10-02],
               "observations" => "Station située au niveau -1 du parking",
               "date_maj" => ~D[2024-10-17],
               "cable_t2_attache" => false
             }
           ]
  end
end
