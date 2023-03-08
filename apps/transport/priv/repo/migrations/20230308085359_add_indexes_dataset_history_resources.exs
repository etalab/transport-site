defmodule DB.Repo.Migrations.AddIndexesDatasetHistoryResources do
  use Ecto.Migration

  def change do
    create_if_not_exists(index(:dataset_history_resources, [:resource_id]))
    create_if_not_exists(index(:dataset_history_resources, [:resource_history_id]))
    create_if_not_exists(index(:dataset_history_resources, [:resource_metadata_id]))
    create_if_not_exists(index(:dataset_history_resources, [:validation_id]))
  end
end
