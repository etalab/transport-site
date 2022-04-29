defmodule DB.Repo.Migrations.SetUpValidationV2 do
  use Ecto.Migration

  def change do
    create table(:multi_validations) do
      add :validation_timestamp, :utc_datetime_usec, null: false
      add :validator, :text, null: false
      add :transport_tools_version, :text
      add :command, :text
      add :result, :jsonb
      add :data_vis, :jsonb
      add :metadata, :jsonb

      add :resource_id, references(:resource, on_delete: :delete_all)
      add :resource_history_id, references(:resource_history, on_delete: :delete_all)
      add :validated_data_name, :text

      add :secondary_resource_id, references(:resource, on_delete: :delete_all)
      add :secondary_resource_history_id, references(:resource_history, on_delete: :delete_all)
      add :secondary_validated_data_name, :text

      timestamps([type: :utc_datetime_usec])
    end
  end
end
