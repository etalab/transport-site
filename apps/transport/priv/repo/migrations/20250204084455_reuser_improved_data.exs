defmodule DB.Repo.Migrations.ReuserImprovedData do
  use Ecto.Migration

  def change do
    create table(:reuser_improved_data) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:resource_id, references(:resource, on_delete: :delete_all), null: false)
      add(:contact_id, references(:contact, on_delete: :delete_all), null: false)
      add(:organization_id, references(:organization, type: :string, on_delete: :delete_all), null: false)
      add(:download_url, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:reuser_improved_data, [:dataset_id]))
    create(index(:reuser_improved_data, [:organization_id]))
    create(unique_index(:reuser_improved_data, [:resource_id, :organization_id]))
  end
end
