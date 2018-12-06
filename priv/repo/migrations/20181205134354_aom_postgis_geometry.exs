defmodule Transport.Repo.Migrations.AomPostgisGeometry do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS postgis"

    alter table(:aom) do
      add :geom, :geometry
    end
    create index("aom", [:geom], using: :gist)

    execute "UPDATE aom SET geom=st_geomFromGeoJson(geometry::text)"
  end

  def down do
    alter table(:aom) do
      remove :geom
    end

    execute "DROP EXTENSION IF EXISTS postgis"
  end
end
