defmodule DB.Repo.Migrations.AddDatasetLegalOwner do
  use Ecto.Migration

  def change do
    create table(:dataset_aom_legal_owner, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:aom_id, references(:aom, on_delete: :delete_all), null: false)
    end

    create(index("dataset_aom_legal_owner", [:dataset_id]))
    create(index("dataset_aom_legal_owner", [:aom_id]))

    create table(:dataset_region_legal_owner, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:region_id, references(:region, on_delete: :delete_all), null: false)
    end

    create(index("dataset_region_legal_owner", [:dataset_id]))
    create(index("dataset_region_legal_owner", [:region_id]))

    alter table(:dataset) do
      add(:legal_owner_company_siren, :integer)
    end
  end
end
