defmodule DB.IrveValidPdc do
  @moduledoc """
  IRVE Point de Charge (PDC) record from a validated IRVE file.
  This schema reflects the IRVE static schema, plus a reference to the IRVE valid file it belongs to.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "irve_valid_pdc" do
    belongs_to(:irve_valid_file, DB.IrveValidFile)

    # IRVE Schema fields
    field(:nom_amenageur, :string)
    field(:siren_amenageur, :string)
    field(:contact_amenageur, :string)
    field(:nom_operateur, :string)
    field(:contact_operateur, :string)
    field(:telephone_operateur, :string)
    field(:nom_enseigne, :string)
    field(:id_station_itinerance, :string)
    field(:id_station_local, :string)
    field(:nom_station, :string)
    field(:implantation_station, :string)
    field(:adresse_station, :string)
    field(:code_insee_commune, :string)
    field(:coordonneesxy, :string)
    field(:nbre_pdc, :integer)
    field(:id_pdc_itinerance, :string)
    field(:id_pdc_local, :string)
    field(:puissance_nominale, :decimal)
    field(:prise_type_ef, :boolean)
    field(:prise_type_2, :boolean)
    field(:prise_type_combo_ccs, :boolean)
    field(:prise_type_chademo, :boolean)
    field(:prise_type_autre, :boolean)
    field(:gratuit, :boolean)
    field(:paiement_acte, :boolean)
    field(:paiement_cb, :boolean)
    field(:paiement_autre, :boolean)
    field(:tarification, :string)
    field(:condition_acces, :string)
    field(:reservation, :boolean)
    field(:horaires, :string)
    field(:accessibilite_pmr, :string)
    field(:restriction_gabarit, :string)
    field(:station_deux_roues, :boolean)
    field(:raccordement, :string)
    field(:num_pdl, :string)
    field(:date_mise_en_service, :date)
    field(:observations, :string)
    field(:date_maj, :date)
    field(:cable_t2_attache, :boolean)

    timestamps(type: :utc_datetime_usec)
  end
end
