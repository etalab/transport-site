defmodule DB.Repo.Migrations.CreateDatasetHistory do
  use Ecto.Migration

  def change do
    create table(:dataset_history) do
      add :dataset_id, references(:dataset, on_delete: :nothing)
      add :dataset_datagouv_id, :text
      add :payload, :jsonb

      timestamps([type: :utc_datetime_usec])
    end

    create_if_not_exists(index(:dataset_history, [:dataset_id]))

    create table(:dataset_history_resources) do
      add :dataset_history_id, references(:dataset_history)
      add :resource_id, references(:resource, on_delete: :nothing)
      add :resource_history_id, references(:resource_history, on_delete: :nothing)
      add :resource_history_last_up_to_date_at, :utc_datetime_usec
      add :resource_metadata_id, references(:resource_metadata, on_delete: :nothing)
      add :validation_id, references(:multi_validation, on_delete: :nothing)
      add :payload, :jsonb
    end

    create_if_not_exists(index(:dataset_history_resources, [:dataset_history_id]))
  end
end
