defmodule DB.Repo.Migrations.PlacesAddOffers do
  use Ecto.Migration

  def up do
    # we drop the old 'places' view, before recreating it
    execute("DROP TRIGGER IF EXISTS refresh_places_region_trigger ON administrative_division;")
    execute("DROP FUNCTION refresh_places;")
    execute("DROP MATERIALIZED VIEW places;")

    execute("""
    CREATE MATERIALIZED VIEW places AS
    SELECT nom, place_id, type, indexed_name
    FROM
    (
        (
          SELECT
            ad.nom AS nom,
            ad.insee AS place_id,
            ad.type AS type,
            unaccent(replace(ad.nom, ' ', '-')) AS indexed_name
          FROM administrative_division ad
          WHERE ad.type in ('commune', 'epci', 'departement', 'region')
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
        UNION
        (
          SELECT nom_commercial AS nom,
          identifiant_offre::varchar as place_id,
          'offer' AS type,
          unaccent(replace(nom_commercial, ' ', '-')) AS indexed_name
          FROM offer
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

    execute("""
    CREATE TRIGGER refresh_places_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON administrative_division
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)

    execute("""
    CREATE TRIGGER refresh_places_trigger
    AFTER INSERT OR UPDATE OR DELETE
    ON offer
    FOR EACH STATEMENT
    EXECUTE PROCEDURE refresh_places();
    """)
  end

  def down, do: IO.puts("No going back")
end
