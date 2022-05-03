defmodule DB.Repo.Migrations.AddCommunesToView do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE OR REPLACE VIEW dataset_geographic_view AS
      SELECT
        id as dataset_id,
        COALESCE(
          -- We take either directly the region
          region_id,
          -- Or the region of the aom
          (SELECT region_id FROM aom WHERE aom.id = aom_id),
          -- Or the region of a random city linked to the dataset
          (SELECT
            region_id
            FROM aom
            WHERE aom.id IN
              (SELECT
                max(commune.aom_res_id)
                FROM commune
                LEFT JOIN dataset_communes ON dataset.id = dataset_communes.dataset_id
              )
          )
        ) as region_id,
        COALESCE(
          (SELECT aom.geom FROM aom WHERE aom.id = aom_id),
          (SELECT region.geom FROM region WHERE region.id = region_id),
          -- If the dataset is linked to cities, we get the union of the cities's geometry
          (SELECT
            ST_UNION(commune.geom)
            FROM commune
            LEFT JOIN dataset_communes ON commune.id = dataset_communes.commune_id
            WHERE dataset_communes.dataset_id = dataset.id
          )
        ) as geom
      FROM dataset;
      """,
      # replace back old view (from 20200114143832_add_dataset_view.exs)
      """
      CREATE OR REPLACE VIEW dataset_geographic_view AS
      SELECT
        id as dataset_id,
        COALESCE(region_id, (SELECT region_id FROM aom WHERE aom.id = aom_id)) as region_id,
        COALESCE((SELECT aom.geom FROM aom WHERE aom.id = aom_id), (SELECT region.geom FROM region WHERE region.id = region_id)) as geom
      FROM dataset;
      """
    )
  end
end
