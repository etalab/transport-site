defmodule DB.Repo.Migrations.UpdateModesFeaturesPlaces do
  use Ecto.Migration

  def up do
    # we drop the old 'places' view, before recreating it
    execute("DROP TRIGGER IF EXISTS refresh_places_region_trigger ON region;")
    execute("DROP TRIGGER IF EXISTS refresh_places_aom_trigger ON aom;")
    execute("DROP TRIGGER IF EXISTS refresh_places_commune_trigger ON commune;")
    execute("DROP FUNCTION refresh_places;")
    execute("DROP MATERIALIZED VIEW places;")

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
        UNION
        (
          SELECT features AS nom,
          features AS place_id,
          'feature' AS type,
          unaccent(replace(features, ' ', '-')) AS indexed_name
          FROM (
          SELECT DISTINCT(UNNEST(features)) as features FROM resource_metadata
          ) as features
        )
        UNION
        (
          SELECT modes AS nom,
          modes AS place_id,
          'mode' AS type,
          unaccent(replace(modes, ' ', '-')) AS indexed_name
          FROM (
          SELECT DISTINCT(UNNEST(modes)) as modes FROM resource_metadata
          ) as modes
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
     # we drop the old 'places' view, before recreating it
    execute("DROP TRIGGER IF EXISTS refresh_places_region_trigger ON region;")
    execute("DROP TRIGGER IF EXISTS refresh_places_aom_trigger ON aom;")
    execute("DROP TRIGGER IF EXISTS refresh_places_commune_trigger ON commune;")
    execute("DROP FUNCTION refresh_places;")
    execute("DROP MATERIALIZED VIEW places;")

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
        UNION
        (
          SELECT features AS nom,
          features AS place_id,
          'feature' AS type,
          unaccent(replace(features, ' ', '-')) AS indexed_name
          FROM (
          SELECT DISTINCT(UNNEST(features)) as features FROM resource
          ) as features
        )
        UNION
        (
          SELECT modes AS nom,
          modes AS place_id,
          'mode' AS type,
          unaccent(replace(modes, ' ', '-')) AS indexed_name
          FROM (
          SELECT DISTINCT(UNNEST(modes)) as modes FROM resource
          ) as modes
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

    execute("""
    CREATE TRIGGER refresh_places_resources_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON resource
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)
    end
  end
