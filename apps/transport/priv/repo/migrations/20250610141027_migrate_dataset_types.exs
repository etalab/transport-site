defmodule DB.Repo.Migrations.MigrateDatasetTypes do
  use Ecto.Migration

  def up do
    execute("UPDATE dataset SET type = 'public-transit' WHERE type = 'air-transport'")
    execute("UPDATE dataset SET type = 'bike-data' WHERE type IN ('bike-way', 'bike-parking')")
    execute("UPDATE dataset SET type = 'road-data' WHERE type IN ('private-parking', 'low-emission-zones')")
    execute("UPDATE dataset SET type = 'informations' WHERE type IN ('locations', 'transport-traffic')")
    execute("UPDATE dataset SET type = 'pedestrian-path' WHERE custom_title ILIKE '%cheminements piétons%'")
    execute("UPDATE dataset SET type = 'vehicles-sharing' WHERE type IN ('bike-scooter-sharing', 'car-motorbike-sharing')")
  end

  def down, do: IO.puts("No going back")
end
