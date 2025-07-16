defmodule DB.Repo.Migrations.CreateDatasetNewCoveredArea do
  use Ecto.Migration

  def change do
    create table(:dataset_declarative_spatial_area, primary_key: false) do
      add(:dataset_id, references(:dataset, on_delete: :delete_all), null: false)
      add(:administrative_division_id, references(:administrative_division, on_delete: :delete_all), null: false)
    end
  end
end
