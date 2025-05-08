defmodule Transport.IRVE.Processing do
  @moduledoc """
  A module able to take raw binary (CSV body), remap it as a `DataFrame`,
  and most importantly preprocess a couple of data.
  """

  @doc """
  Takes a CSV body, read it as `DataFrame`, then preprocess all the required fields
  """
  def read_as_data_frame(body) do
    # TODO: be smooth about `cable_t2_attache` - only added in v2.1.0 (https://github.com/etalab/schema-irve/releases/tag/v2.1.0)
    # and often not provided
    Transport.IRVE.DataFrame.dataframe_from_csv_body!(
      body,
      Transport.IRVE.StaticIRVESchema.schema_content(),
      _strict = false
    )
    |> Transport.IRVE.DataFrame.preprocess_xy_coordinates()
    |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_ef")
    |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_2")
    |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_combo_ccs")
    |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_chademo")
    |> Transport.IRVE.DataFrame.preprocess_boolean("prise_type_autre")
    |> Transport.IRVE.DataFrame.preprocess_boolean("gratuit")
    |> Transport.IRVE.DataFrame.preprocess_boolean("paiement_acte")
    |> Transport.IRVE.DataFrame.preprocess_boolean("paiement_cb")
    |> Transport.IRVE.DataFrame.preprocess_boolean("paiement_autre")
    |> Transport.IRVE.DataFrame.preprocess_boolean("reservation")
    |> Transport.IRVE.DataFrame.preprocess_boolean("station_deux_roues")
    |> Explorer.DataFrame.select([
      "nom_amenageur",
      "siren_amenageur",
      "contact_amenageur",
      "nom_operateur",
      "contact_operateur",
      "telephone_operateur",
      "nom_enseigne",
      "id_station_itinerance",
      "id_station_local",
      "nom_station",
      "implantation_station",
      "adresse_station",
      "code_insee_commune",
      # "coordonneesXY",
      "nbre_pdc",
      "id_pdc_itinerance",
      "id_pdc_local",
      "puissance_nominale",
      "prise_type_ef",
      "prise_type_2",
      "prise_type_combo_ccs",
      "prise_type_chademo",
      "prise_type_autre",
      "gratuit",
      "paiement_acte",
      "paiement_cb",
      "paiement_autre",
      "tarification",
      "condition_acces",
      "reservation",
      "horaires",
      "accessibilite_pmr",
      "restriction_gabarit",
      "station_deux_roues",
      "raccordement",
      "num_pdl",
      "date_mise_en_service",
      "observations",
      "date_maj",
      # "cable_t2_attache",
      # extracted
      "x",
      "y"
    ])
  end
end
