defmodule DB.Repo.Migrations.CreateGtfsStopsTable do
  use Ecto.Migration

  def change do
    create table(:data_import) do
      add :resource_history_id, references(:resource_history)
    end

    create table(:gtfs_stops) do
      add(:data_import_id, references(:data_import))
      add(:stop_id, :binary)
      add(:stop_name, :binary)
      add(:stop_lat, :float)
      add(:stop_lon, :float)
      add(:location_type, :binary)
    end

    create table(:gtfs_calendar) do
      add(:data_import_id, references(:data_import))
      add(:service_id, :binary)
      add(:monday, :integer)
      add(:tuesday, :integer)
      add(:wednesday, :integer)
      add(:thursday, :integer)
      add(:friday, :integer)
      add(:saturday, :integer)
      add(:sunday, :integer)
      add(:start_date, :date)
      add(:end_date, :date)
    end
  end
end
