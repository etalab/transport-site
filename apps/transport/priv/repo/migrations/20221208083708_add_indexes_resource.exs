defmodule DB.Repo.Migrations.AddIndexesResource do
  use Ecto.Migration

  def change do
    create_if_not_exists(index(:resource_history, [:resource_id]))
    create_if_not_exists(index(:multi_validation, [:resource_id]))
    create_if_not_exists(index(:resource_metadata, [:resource_id]))
    create_if_not_exists(index(:resource, [:dataset_id]))
  end
end
