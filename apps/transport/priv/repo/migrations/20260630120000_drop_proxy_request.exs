defmodule DB.Repo.Migrations.DropProxyRequest do
  use Ecto.Migration

  # First step of the TimescaleDB removal.
  def up do
    drop_if_exists(table(:proxy_request))
  end

  def down do
    raise "non-reversible migration: proxy_request hypertable was dropped"
  end
end
