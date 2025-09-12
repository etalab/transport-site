defmodule DB.IRVEValidPDC do
  @moduledoc """
  IRVE Point de Charge (PDC) record from a validated IRVE file.
  This schema reflects the IRVE static schema, plus a reference to the IRVE valid file it belongs to.
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
    |> split_coordinates()
    |> Map.update(:date_mise_en_service, nil, &parse_date/1)
    |> Map.update(:date_maj, nil, &parse_date/1)
  end

  def insert_timestamps(data) do
    now = DateTime.utc_now()

    data
    |> Map.put(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp split_coordinates(%{longitude: _longitude, latitude: _latitude} = map), do: map

  defp split_coordinates(%{coordonneesXY: coords} = map) do
    [longitude, latitude] = process_coordinates(coords)

    map
    |> Map.delete(:coordonneesXY)
    |> Map.put(:longitude, longitude)
    |> Map.put(:latitude, latitude)
  end

  @doc """
  iex> process_coordinates("[7.48710500,48.345345]")
  [7.48710500, 48.345345]
  """
  def process_coordinates(coords) do
    coords
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.to_float/1)
  end

  defp parse_date(date_string) when is_binary(date_string) do
    Date.from_iso8601!(date_string)
  end

  defp parse_date(%Date{} = date), do: date

  defp valid_fields,
    do: Transport.IRVE.StaticIRVESchema.field_names_list() ++ ["id", "irve_valid_file_id", "longitude", "latitude"]
end
