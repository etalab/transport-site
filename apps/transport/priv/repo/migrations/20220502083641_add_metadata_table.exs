defmodule DB.Repo.Migrations.AddMetadataTable do
  use Ecto.Migration

  def change do
    create table(:resource_metadata) do
      add :resource_id, references(:resource, on_delete: :delete_all)
      add :resource_history_id, references(:resource_history, on_delete: :delete_all)
      add :multi_validation_id, references(:multi_validation, on_delete: :delete_all)
      add :metadata, :jsonb

      timestamps([type: :utc_datetime_usec])
    end
  end
end
