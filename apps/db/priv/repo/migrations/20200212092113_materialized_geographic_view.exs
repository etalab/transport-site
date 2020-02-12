defmodule DB.Repo.Migrations.MaterializedGeographicView do
  @moduledoc """
  Replace the view by a materialized view,
  since we do lots of join on this view the performance
  will be way better with a materialized view
  """
  use Ecto.Migration

  def up do
    # drop the old 'classic' view
    execute("DROP VIEW dataset_geographic_view;")

    execute("""
    CREATE MATERIALIZED VIEW dataset_geographic_view AS
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
    FROM dataset
    WITH DATA;
    """)

    # Add an index on dataset_id since we'll often make a join on this
    execute("CREATE INDEX dataset_id_idx ON dataset_geographic_view (dataset_id);")

    # Define a trigger function to refresh the materialized view
    execute("""
    CREATE OR REPLACE FUNCTION refresh_dataset_geographic_view()
    RETURNS trigger AS $$
    BEGIN
      REFRESH MATERIALIZED VIEW dataset_geographic_view;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Call of the trigger
    execute("""
    CREATE TRIGGER refresh_dataset_geographic_view_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON dataset
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_dataset_geographic_view();
    """)
  end

  def down do
    # put back the old view
    execute("DROP TRIGGER refresh_dataset_geographic_view_trigger ON dataset;")
    execute("DROP FUNCTION refresh_dataset_geographic_view;")
    execute("DROP MATERIALIZED VIEW dataset_geographic_view;")

    execute("""
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
    """)
  end
end
