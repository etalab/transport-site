defmodule DB.Repo.Migrations.AddProxyMetrics do
  use Ecto.Migration

  def change do
    create table("metrics") do
      add :target, :string, null: false
      add :event, :string, null: false
      add :period, :timestamp, null: false
      add :count, :integer, default: 0, null: false

      timestamps([type: :utc_datetime_usec])
    end

    create index("metrics", [:target, :event, :period], unique: true)
  end
end
