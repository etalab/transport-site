defmodule DB.Repo.Migrations.DatasetCommunesOnDelete do
@moduledoc """
  the on_delete action were misplaced in 20200116092044_link_dataset_commune.exs
  but you cannot alter a table when a view depends on that table. So I need to delete the dataset_geographic_view and
  its trigger, alter the table dataset_communes, and recreate the view.
  The code to create the view is taken from the previous migration 20210622150648_dataset_communes_on_delete.exs
"""
  use Ecto.Migration

  def up do
    drop_materialized_view()

    drop constraint(:dataset_communes, "dataset_communes_commune_id_fkey")
    drop constraint(:dataset_communes, "dataset_communes_dataset_id_fkey")
    alter table(:dataset_communes) do
        modify :dataset_id, references(:dataset, on_delete: :delete_all)
        modify :commune_id, references(:commune, on_delete: :delete_all)
    end

    recreate_materialized_view()
  end

  def down do
    drop_materialized_view()

    drop constraint(:dataset_communes, "dataset_communes_commune_id_fkey")
    drop constraint(:dataset_communes, "dataset_communes_dataset_id_fkey")
    alter table(:dataset_communes) do
        modify :dataset_id, references(:dataset)
        modify :commune_id, references(:commune)
    end

    recreate_materialized_view()
  end

  def drop_materialized_view() do
    execute("DROP TRIGGER refresh_dataset_geographic_view_trigger ON dataset;")
    execute("DROP FUNCTION refresh_dataset_geographic_view;")
    execute("DROP MATERIALIZED VIEW dataset_geographic_view;")
  end

  def recreate_materialized_view() do
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
          (SELECT c.region_id
            FROM dataset_communes dc
            LEFT JOIN commune c
            ON dc.commune_id = c.id
            WHERE dc.dataset_id = dataset.id
            order BY aom_res_id desc
            LIMIT 1
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
end
