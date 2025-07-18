defmodule Transport.IRVE.Processing do
  @moduledoc """
  Leverages `Transport.IRVE.DataFrame` (see more doc there) and `Explorer.DataFrame` to read
  and preprocess (to some extent) a raw CSV binary body.
  """

  @doc """
  Takes a CSV body, read it as `DataFrame`, then preprocess all the required fields.
  """
  def read_as_data_frame(body) do
    body
    |> convert_to_dataframe!()
    |> preprocess_fields()
    |> select_fields()
  end

  def convert_to_dataframe!(body) do
    # TODO: be smooth about `cable_t2_attache` - only added in v2.1.0 (https://github.com/etalab/schema-irve/releases/tag/v2.1.0)
    # and often not provided
    body
    |> Transport.IRVE.DataFrame.dataframe_from_csv_body!(
      Transport.IRVE.StaticIRVESchema.schema_content(),
      # NOTE: we read as non-strict (impacts booleans at time of writing)
      # because we manually reprocess them right here after.
      _strict = false
    )
  end

  def preprocess_fields(dataframe) do
    dataframe
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
  end

  def select_fields(dataframe) do
    dataframe
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
      # NOTE: replaced & split into `x` and `y` down there instead
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
