defmodule DB.Repo.Migrations.CreateGtfsStopsTable do
  use Ecto.Migration

  def change do
    create table(:gtfs_import) do
      add :resource_history_id, references(:resource_history)
    end

    create table(:gtfs_stops) do
      add(:gtfs_import_id, references(:gtfs_import))
      add(:stop_id, :binary)
      add(:stop_name, :binary)
      add(:stop_lat, :float)
      add(:stop_lon, :float)
      add(:location_type, :binary)
    end
  end
end
