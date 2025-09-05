defmodule DB.Repo.Migrations.CreateIrveTables do
  use Ecto.Migration

  def change do
    create table(:irve_valid_file) do
      add(:dataset_datagouv_id, :string, null: false)
      add(:resource_datagouv_id, :string, null: false)
      add(:checksum, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create table(:irve_valid_pdc) do
      add(:irve_valid_file_id, references(:irve_valid_file, on_delete: :delete_all), null: false)

      # IRVE Schema fields
      add(:nom_amenageur, :string)
      add(:siren_amenageur, :string)
      add(:contact_amenageur, :string)
      add(:nom_operateur, :string)
      add(:contact_operateur, :string, null: false)
      add(:telephone_operateur, :string)
      add(:nom_enseigne, :string, null: false)
      add(:id_station_itinerance, :string, null: false)
      add(:id_station_local, :string)
      add(:nom_station, :string, null: false)
      add(:implantation_station, :string, null: false)
      add(:adresse_station, :string, null: false)
      add(:code_insee_commune, :string)
      add(:coordonneesxy, :string, null: false)
      add(:nbre_pdc, :integer, null: false)
      add(:id_pdc_itinerance, :string, null: false)
      add(:id_pdc_local, :string)
      add(:puissance_nominale, :decimal, null: false)
      add(:prise_type_ef, :boolean, null: false)
      add(:prise_type_2, :boolean, null: false)
      add(:prise_type_combo_ccs, :boolean, null: false)
      add(:prise_type_chademo, :boolean, null: false)
      add(:prise_type_autre, :boolean, null: false)
      add(:gratuit, :boolean)
      add(:paiement_acte, :boolean, null: false)
      add(:paiement_cb, :boolean)
      add(:paiement_autre, :boolean)
      add(:tarification, :text)
      add(:condition_acces, :text, null: false)
      add(:reservation, :boolean, null: false)
      add(:horaires, :string, null: false)
      add(:accessibilite_pmr, :string, null: false)
      add(:restriction_gabarit, :string, null: false)
      add(:station_deux_roues, :boolean, null: false)
      add(:raccordement, :string)
      add(:num_pdl, :string)
      add(:date_mise_en_service, :date)
      add(:observations, :text)
      add(:date_maj, :date, null: false)
      add(:cable_t2_attache, :boolean)

      timestamps(type: :utc_datetime_usec)
    end

    # Comment for review: unsure if needed
    create(index(:irve_valid_file, [:dataset_datagouv_id]))
    create(index(:irve_valid_file, [:resource_datagouv_id]))
    # Same
    create(index(:irve_valid_file, [:checksum]))
    # Same
    create(unique_index(:irve_valid_file, [:resource_datagouv_id, :checksum]))

    create(index(:irve_valid_pdc, [:irve_valid_file_id]))
    # Same
    create(index(:irve_valid_pdc, [:id_pdc_itinerance]))
  end
end
