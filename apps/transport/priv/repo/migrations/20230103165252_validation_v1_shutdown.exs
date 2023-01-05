defmodule DB.Repo.Migrations.ValidationV1Shutdown do
  use Ecto.Migration

  def up do
    drop table(:logs_validation)
    drop table(:validations)
    alter table(:resource) do
      remove :metadata
      remove :content_hash
      remove :modes
      remove :features
    end
  end

  def down do
    create table(:logs_validation) do
      add :resource_id, references(:resource)
      add :timestamp, :utc_datetime
      add :is_success, :boolean
      add :error_msg, :text
      add :skipped, :boolean, default: false
      add :skipped_reason, :string
    end

    create table(:validations) do
      add :details, :jsonb
      add :date, :string
      add :resource_id, references(:resource, on_delete: :delete_all)
      add :max_error, :string
      add :validation_latest_content_hash, :string
      add :on_the_fly_validation_metadata, :jsonb
      add :data_vis, :jsonb
    end

    alter table(:resource) do
      add :metadata, :jsonb
      add :content_hash, :string
      add :modes, {:array, :string}, default: []
      add :features, {:array, :string}, default: []
    end
  end
end
