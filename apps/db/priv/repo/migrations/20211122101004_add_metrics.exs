defmodule DB.Repo.Migrations.AddProxyMetrics do
  use Ecto.Migration

  def change do
    create table("proxy_metrics") do
      add :resource_identifier, :string, null: false
      add :event, :string, null: false
      add :period, :timestamp, null: false
      add :count, :integer, default: 0, null: false

      timestamps([type: :utc_datetime_usec])
    end

    create index("proxy_metrics", [:resource_identifier, :event, :period], unique: true)
  end
end
