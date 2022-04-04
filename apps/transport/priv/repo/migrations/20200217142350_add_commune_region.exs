defmodule DB.Repo.Migrations.AddCommuneRegion do
  use Ecto.Migration

  def up do
    alter table(:commune) do
      add(:region_id, references(:region))
    end

    create(index("commune", [:geom], using: :gist))

    create(index("region", [:geom], using: :gist))
    execute("UPDATE region SET geom = ST_SETSRID(region.geom, 4326)")

    execute("""
    UPDATE commune c1 SET region_id = (
      SELECT region.id
      FROM commune c2, region
      WHERE c1.id = c2.id
            AND ST_AREA(
                ST_BUFFER(
                  ST_INTERSECTION(ST_BUFFER(region.geom, 0), ST_BUFFER(c2.geom, 0)
                ), 0)
              )
              / ST_AREA(c2.geom) > 0.9
            AND c2.geom && region.geom
            AND region.geom IS NOT NULL
            AND c2.geom IS NOT NULL
            LIMIT 1
      );
    """)
  end

  def down do
    alter table(:commune) do
      remove(:region_id)
    end

    drop(index("commune", [:geom]))
    drop(index("region", [:geom]))
  end
end
