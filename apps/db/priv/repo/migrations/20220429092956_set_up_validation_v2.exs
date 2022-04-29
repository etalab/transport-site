defmodule DB.Repo.Migrations.SetUpValidationV2 do
  use Ecto.Migration

  def change do
    create table(:multi_validations) do
      add :validation_timestamp, :utc_datetime, null: false
      add :validator, :string, null: false
      add :transport_tools_version, :string
      add :command, :string
      add :result, :jsonb
      add :data_vis, :jsonb

      add :resource_id, references(:resource, on_delete: :delete_all)
      add :resource_history_id, references(:resource_history, on_delete: :delete_all)
      add :validated_data_name, :string

      add :secondary_resource_id, references(:resource, on_delete: :delete_all)
      add :secondary_resource_history_id, references(:resource_history, on_delete: :delete_all)
      add :secondary_validated_data_name, :string

      timestamps([type: :utc_datetime_usec])
    end
  end
end
