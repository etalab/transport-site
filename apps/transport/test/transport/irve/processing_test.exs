defmodule Transport.IRVE.ProcessingTest do
  use ExUnit.Case, async: true
  doctest Transport.IRVE.Processing, import: true

  test "Read as DataFrame" do
    row =
      DB.Factory.IRVE.generate_row(%{
        "prise_type_ef" => "FAUX",
        "prise_type_2" => 1
      })
      |> Map.delete("tarification")

    body = [row] |> DB.Factory.IRVE.to_csv_body()
    df = Transport.IRVE.Processing.read_as_data_frame(body)
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
               "implantation_station" => "Lieu de ma station",
               "adresse_station" => "26 rue des écluses, 17430 Champdolent",
               "code_insee_commune" => "17085",
               "nbre_pdc" => 1,
               "id_pdc_itinerance" => "FRPAN99E12345678",
               "id_pdc_local" => "pdc_001",
               "puissance_nominale" => 22,
               # This was converted
               "prise_type_ef" => false,
               # This was converted too
               "prise_type_2" => true,
               "prise_type_combo_ccs" => false,
               "prise_type_chademo" => false,
               "prise_type_autre" => false,
               "gratuit" => false,
               "paiement_acte" => true,
               "paiement_cb" => true,
               "paiement_autre" => true,
               # This was added
               "tarification" => nil,
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
               # This was added and coordonneesXY removed
               "x" => -0.799141,
               # Same
               "y" => 45.91914
             }
           ]
  end
end
