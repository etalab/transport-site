defmodule DB.Repo.Migrations.AddDatasetView do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE VIEW dataset_geographic_view AS
      SELECT
        id as dataset_id,
        COALESCE(region_id, (SELECT region_id FROM aom WHERE aom.id = aom_id)) as region_id,
        COALESCE((SELECT aom.geom FROM aom WHERE aom.id = aom_id), (SELECT region.geom FROM region WHERE region.id = region_id)) as geom
      FROM dataset;
      """,
      "DROP VIEW dataset_geographic_view;"
    )
  end
end
