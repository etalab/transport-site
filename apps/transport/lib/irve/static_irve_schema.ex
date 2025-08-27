defmodule Transport.IRVE.StaticIRVESchema do
  @moduledoc """
  A module providing programmatic access to the static IRVE schema,
  as stored in the source code.
  """

  @doc """
  Read & decode the content of the IRVE static schema.

  NOTE: this is not cached at the moment.
  """
  def schema_content do
    __DIR__
    |> Path.join("../../../shared/meta/schema-irve-statique.json")
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Field names list from the json schema
  iex> field_names_list()
  ["nom_amenageur", "siren_amenageur", "contact_amenageur", "nom_operateur",
  "contact_operateur", "telephone_operateur", "nom_enseigne",
  "id_station_itinerance", "id_station_local", "nom_station",
  "implantation_station", "adresse_station", "code_insee_commune",
  "coordonneesXY", "nbre_pdc", "id_pdc_itinerance", "id_pdc_local",
  "puissance_nominale", "prise_type_ef", "prise_type_2", "prise_type_combo_ccs",
  "prise_type_chademo", "prise_type_autre", "gratuit", "paiement_acte",
  "paiement_cb", "paiement_autre", "tarification", "condition_acces",
  "reservation", "horaires", "accessibilite_pmr", "restriction_gabarit",
  "station_deux_roues", "raccordement", "num_pdl", "date_mise_en_service",
  "observations", "date_maj", "cable_t2_attache"]
  """
  def field_names_list do
    schema_content()
    |> Map.fetch!("fields")
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  @doc """
  Useful for reprocessing boolean fields
  iex> boolean_columns()
  [
              "prise_type_ef",
              "prise_type_2",
              "prise_type_combo_ccs",
              "prise_type_chademo",
              "prise_type_autre",
              "gratuit",
              "paiement_acte",
              "paiement_cb",
              "paiement_autre",
              "reservation",
              "station_deux_roues",
              "cable_t2_attache"
            ]
  """

  def boolean_columns do
    schema_content()
    |> Map.fetch!("fields")
    |> Enum.filter(&(&1["type"] == "boolean"))
    |> Enum.map(&Map.fetch!(&1, "name"))
  end
end
