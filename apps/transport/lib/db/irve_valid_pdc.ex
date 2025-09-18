defmodule DB.IRVEValidPDC do
  @moduledoc """
  IRVE Point de Charge (PDC) record from a validated IRVE file.
  This schema reflects the IRVE static schema, plus a reference to the IRVE valid file it belongs to.
  Generating data from raw CSV rows ready to be inserted in the database needs some preprocessing.
  Use first Transport.IRVE.Processing for work on coordinates.
  Then use `raw_data_to_schema/1` to filter out only valid fields and convert keys to atoms.
  Finally use `insert_timestamps/1` to add inserted_at and updated_at timestamps before inserting in the database.
  See Transport.IRVE.DatabaseImporter for a module that orchestrates the whole import process.
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "irve_valid_pdc" do
    belongs_to(:irve_valid_file, DB.IRVEValidFile)

    # IRVE Schema fields
    field(:nom_amenageur, :string)
    field(:siren_amenageur, :string)
    field(:contact_amenageur, :string)
    field(:nom_operateur, :string)
    field(:contact_operateur, :string, null: false)
    field(:telephone_operateur, :string)
    field(:nom_enseigne, :string, null: false)
    field(:id_station_itinerance, :string, null: false)
    field(:id_station_local, :string)
    field(:nom_station, :string, null: false)
    field(:implantation_station, :string, null: false)
    field(:adresse_station, :string, null: false)
    field(:code_insee_commune, :string)
    field(:nbre_pdc, :integer, null: false)
    field(:id_pdc_itinerance, :string, null: false)
    field(:id_pdc_local, :string)
    field(:puissance_nominale, :decimal, null: false)
    field(:prise_type_ef, :boolean, null: false)
    field(:prise_type_2, :boolean, null: false)
    field(:prise_type_combo_ccs, :boolean, null: false)
    field(:prise_type_chademo, :boolean, null: false)
    field(:prise_type_autre, :boolean, null: false)
    field(:gratuit, :boolean)
    field(:paiement_acte, :boolean, null: false)
    field(:paiement_cb, :boolean)
    field(:paiement_autre, :boolean)
    field(:tarification, :string)
    field(:condition_acces, :string, null: false)
    field(:reservation, :boolean, null: false)
    field(:horaires, :string, null: false)
    field(:accessibilite_pmr, :string, null: false)
    field(:restriction_gabarit, :string, null: false)
    field(:station_deux_roues, :boolean, null: false)
    field(:raccordement, :string)
    field(:num_pdl, :string)
    field(:date_mise_en_service, :date)
    field(:observations, :string)
    field(:date_maj, :date, null: false)
    field(:cable_t2_attache, :boolean)
    field(:longitude, :decimal, null: false)
    field(:latitude, :decimal, null: false)

    timestamps(type: :utc_datetime_usec)
  end

  def raw_data_to_schema(raw_data) do
    raw_data
    |> Enum.filter(fn {k, _v} -> k in valid_fields() end)
    |> Enum.into(%{}, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  def insert_timestamps(data) do
    now = DateTime.utc_now()

    data
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp valid_fields,
    do: Transport.IRVE.StaticIRVESchema.field_names_list() ++ ["id", "irve_valid_file_id", "longitude", "latitude"]
end
