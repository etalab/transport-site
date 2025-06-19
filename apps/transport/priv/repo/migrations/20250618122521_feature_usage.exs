defmodule DB.Repo.Migrations.FeatureUsage do
  use Ecto.Migration
  import Timescale.Migration

  def change do
    create table(:feature_usage, primary_key: false) do
      add(:time, :utc_datetime_usec, null: false)
      add(:feature, :string, null: false)
      add(:contact_id, references(:contact, on_delete: :delete_all))
      add(:metadata, :jsonb)
    end

    timescaledb_available = Enum.member?(postgresql_extensions(), "timescaledb")

    if direction() == :up and timescaledb_available do
      create_timescaledb_extension()
      create_hypertable(:feature_usage, :time)
    end

    if System.get_env("CI") == "true" and not timescaledb_available do
      raise "TimescaleDB should be available in CI"
    end

    create_if_not_exists(index(:feature_usage, [:feature]))
    create_if_not_exists(index(:feature_usage, [:contact_id]))
  end

  def postgresql_extensions do
    %Postgrex.Result{rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, "SELECT extname FROM pg_extension")
    List.flatten(rows)
  end
end
