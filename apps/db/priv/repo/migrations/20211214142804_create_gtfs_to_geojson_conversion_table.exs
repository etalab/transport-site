defmodule DB.Repo.Migrations.CreateGtfsToGeojsonConversionTable do
  use Ecto.Migration

  def change do
    create table("gtfs_to_geojson_conversion") do
      # FIX ME
      # We should be able to add a foreign key to resource.datagouv_id
      # but for now datagouv_id is not unique
      # See https://github.com/etalab/transport-site/issues/1930
      add :datagouv_id, :string, null: false
      add :resource_history_uuid, :string, null: false
      add :payload, :jsonb, null: false

      timestamps([type: :utc_datetime_usec])
    end

    create index("gtfs_to_geojson_conversion", [:datagouv_id, :resource_history_uuid])
  end
end
