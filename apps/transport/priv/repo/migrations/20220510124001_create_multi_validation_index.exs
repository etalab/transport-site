defmodule DB.Repo.Migrations.CreateMultiValidationIndex do
  use Ecto.Migration

  def change do
    create(index(:multi_validation, [:resource_history_id, :validator]))
    create(index(:resource_metadata, [:multi_validation_id]))
  end
end
