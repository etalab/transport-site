defmodule DB.Repo.Migrations.AddDatasetTerritoryTables do
  use Ecto.Migration

  def change do
    create table(:dataset_new_communes, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all))
      add(:commune_insee, references(:commune, type: :string, column: :insee, on_delete: :delete_all))
    end

    create table(:dataset_epcis, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all))
      add(:epci_insee, references(:epci, type: :string, column: :insee, on_delete: :delete_all))
    end

    create table(:dataset_departements, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all))
      add(:departement_insee, references(:departement, type: :string, column: :insee, on_delete: :delete_all))
    end

    create table(:dataset_regions, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all))
      add(:region_insee, references(:region, type: :string, column: :insee, on_delete: :delete_all))
    end
  end
end
