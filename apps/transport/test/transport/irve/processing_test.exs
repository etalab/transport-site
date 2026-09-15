defmodule Transport.IRVE.ProcessingTest do
  use ExUnit.Case, async: true
  doctest Transport.IRVE.Processing, import: true

  defp build_typed_frame(body) do
    body
    |> Transport.IRVE.Processing.read_as_uncasted_data_frame()
    |> Transport.IRVE.Validator.compute_validation()
    |> Transport.IRVE.Processing.cast_validated_frame()
  end

  test "cast_validated_frame/1 produces the typed, insert-ready frame" do
    row =
      DB.Factory.IRVE.generate_row(%{
        "prise_type_ef" => "FAUX",
        "prise_type_2" => 1,
        # NOTE: 22.1 has no exact representation in either
        # f32 or f64 (see https://float.exposed/0.21),
        # so use an exact `Decimal` for the input
        "puissance_nominale" => Decimal.new("22.1")
      })
      |> Map.delete("tarification")

    df = build_typed_frame([row] |> DB.Factory.IRVE.to_csv_body())
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
               "nbre_pdc" => 1,
               "id_pdc_itinerance" => "FRPAN99E12345678",
               "id_pdc_local" => "pdc_001",
               # using f64, while the representation is not exact,
               # the comparison works because it is close enough
               "puissance_nominale" => 22.1,
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
               "longitude" => -0.799141,
               # Same
               "latitude" => 45.91914,
               "consolidated_is_lon_lat_correct" => true
             }
           ]
  end

  test "cast_validated_frame/1 corrects inverted coordinates" do
    body =
      [DB.Factory.IRVE.generate_row(%{"coordonneesXY" => "[45.91914, -0.799141]"})] |> DB.Factory.IRVE.to_csv_body()

    [row] = build_typed_frame(body) |> Explorer.DataFrame.to_rows()

    assert row["longitude"] == -0.799141
    assert row["latitude"] == 45.91914
    assert row["consolidated_is_lon_lat_correct"] == false
  end

  test "cast_validated_frame/1 maps empty values to nil, fully typed" do
    body = [DB.Factory.IRVE.generate_row(%{"gratuit" => "", "observations" => ""})] |> DB.Factory.IRVE.to_csv_body()

    df = build_typed_frame(body)
    [row] = Explorer.DataFrame.to_rows(df)

    assert row["gratuit"] == nil
    assert row["observations"] == nil
    refute :null in Map.values(Explorer.DataFrame.dtypes(df))
    assert Explorer.DataFrame.dtypes(df)["date_maj"] == :date
  end
end
