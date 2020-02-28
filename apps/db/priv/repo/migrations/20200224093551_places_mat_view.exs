defmodule DB.Repo.Migrations.TestPlaces do
  use Ecto.Migration

  def up do
    # we use pg_trgm extension for trigram match
    # This is commented as it requires superuser rights and will fail even if the extension is installed
    # execute("CREATE EXTENSION IF NOT EXISTS pg_trgm;")

    execute("""
    CREATE MATERIALIZED VIEW places AS
    SELECT nom, place_id, type, indexed_name
    FROM
    (
        (
          SELECT
          c.nom AS nom,
          c.insee AS place_id,
          'commune' AS type,
          unaccent(replace(nom, ' ', '-')) AS indexed_name
          FROM commune c
        )
        UNION
        (
          SELECT
          r.nom AS nom,
          CAST(r.id AS varchar) AS place_id,
          'region' AS type,
          unaccent(replace(nom, ' ', '-')) AS indexed_name
          FROM region r
        )
        UNION
        (
          SELECT a.nom AS nom,
          CAST(a.id AS varchar) AS place_id,
          'aom' AS type,
          unaccent(replace(nom, ' ', '-')) AS indexed_name
          FROM aom a
        )
    ) AS place
    WITH DATA
    """)

    execute("CREATE INDEX indexed_name_index ON places USING GIN(indexed_name gin_trgm_ops);")

    # Define a trigger function to refresh the materialized view
    execute("""
    CREATE OR REPLACE FUNCTION refresh_places()
    RETURNS trigger AS $$
    BEGIN
      REFRESH MATERIALIZED VIEW places;
      RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Call of the trigger for region, aom and commune update
    execute("""
    CREATE TRIGGER refresh_places_region_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON region
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)

    execute("""
    CREATE TRIGGER refresh_places_aom_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON aom
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)

    execute("""
    CREATE TRIGGER refresh_places_commune_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON commune
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)
  end

  def down do
    execute("DROP MATERIALIZED VIEW places;")
  end
end
