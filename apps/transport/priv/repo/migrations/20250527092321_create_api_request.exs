defmodule DB.Repo.Migrations.CreateApiRequest do
  use Ecto.Migration
  import Timescale.Migration

  def change do
    create table(:api_request, primary_key: false) do
      add(:time, :utc_datetime_usec, null: false)
      add(:token_id, references(:token, on_delete: :delete_all))
      add(:method, :string, size: 250)
      add(:path, :string, size: 1_000)
    end

    timescaledb_available = Enum.member?(postgresql_extensions(), "timescaledb")

    if direction() == :up and timescaledb_available do
      create_timescaledb_extension()
      create_hypertable(:api_request, :time)
    end

    if System.get_env("CI") == "true" and not timescaledb_available do
      raise "TimescaleDB should be available in CI"
    end

    create_if_not_exists(index(:api_request, [:token_id]))
    create_if_not_exists(index(:api_request, [:method]))
  end

  def postgresql_extensions do
    %Postgrex.Result{rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, "SELECT extname FROM pg_extension")
    List.flatten(rows)
  end
end
