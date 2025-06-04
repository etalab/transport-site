defmodule DB.Repo.Migrations.ResourceDownload do
  use Ecto.Migration
  import Timescale.Migration

  def change do
    create table(:resource_download, primary_key: false) do
      add(:time, :utc_datetime_usec, null: false)
      add(:token_id, references(:token, on_delete: :delete_all))
      add(:resource_id, references(:resource, on_delete: :nothing))
    end

    timescaledb_available = Enum.member?(postgresql_extensions(), "timescaledb")

    if direction() == :up and timescaledb_available do
      create_timescaledb_extension()
      create_hypertable(:resource_download, :time)
    end

    if System.get_env("CI") == "true" and not timescaledb_available do
      raise "TimescaleDB should be available in CI"
    end

    create_if_not_exists(index(:resource_download, [:token_id]))
    create_if_not_exists(index(:resource_download, [:resource_id]))
  end

  def postgresql_extensions do
    %Postgrex.Result{rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, "SELECT extname FROM pg_extension")
    List.flatten(rows)
  end
end
