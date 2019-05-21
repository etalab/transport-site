defmodule Transport.Repo.Migrations.OnlyUsePostgis do
  use Ecto.Migration

  def up do
    alter table(:region) do
      add :geom, :geometry
    end
    execute "UPDATE region SET geom=st_geomFromGeoJson(geometry::text)"

    alter table(:region) do
      remove :geometry
    end

    alter table(:aom) do
      remove :geometry
    end
  end

  def down do
    alter table(:region) do
      remove :geom
      add :geometry, :map
    end

    alter table(:aom) do
      add :geometry, :map
    end
  end
end
