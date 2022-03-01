defmodule DB.Repo.Migrations.AddTableGtfsStopTimes do
  use Ecto.Migration

  def up do
    create table(:gtfs_stop_times) do
      add(:data_import_id, references(:data_import))
      add(:trip_id, :binary)
      add(:stop_id, :binary)
      add(:stop_sequence, :integer)
    end

    execute """
      alter table gtfs_stop_times add column arrival_time interval hour to second;
    """

    execute """
      alter table gtfs_stop_times add column departure_time interval hour to second;
    """
  end

  def down do
    execute "drop table gtfs_stop_times;"
  end
end
