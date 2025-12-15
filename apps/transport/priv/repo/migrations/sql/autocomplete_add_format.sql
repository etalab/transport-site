DROP TRIGGER refresh_autocomplete_trigger ON administrative_division|
DROP TRIGGER refresh_autocomplete_trigger ON offer|

DROP FUNCTION refresh_autocomplete|

DROP MATERIALIZED VIEW autocomplete|

CREATE MATERIALIZED VIEW autocomplete AS
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
        -- GTFS Transport validator
        select distinct unnest(features) features
        from resource_metadata rm
        inner join multi_validation mv on mv.id = rm.multi_validation_id
        where mv.validator in ('GTFS transport-validator')

        union
        -- GTFS-RT validation
        select distinct unnest(features) features
        from resource_metadata rm
        join resource r on r.id = rm.resource_id and r.format = 'gtfs-rt'
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
    UNION
    (
      SELECT r.format AS nom,
      r.format as place_id,
      'format' AS type,
      unaccent(replace(r.format, ' ', '-')) AS indexed_name
      FROM resource r
      JOIN dataset d on d.id = r.dataset_id and d.is_active
      WHERE r.format IS NOT NULL
      GROUP BY r.format
      HAVING count(1) >= 5
    )
) AS place
WITH DATA
|

CREATE INDEX indexed_name_index ON autocomplete USING GIN(indexed_name gin_trgm_ops)|

CREATE OR REPLACE FUNCTION refresh_autocomplete()
RETURNS trigger AS $$
BEGIN
  REFRESH MATERIALIZED VIEW autocomplete;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql|


CREATE TRIGGER refresh_autocomplete_trigger
AFTER INSERT OR UPDATE OR DELETE
ON administrative_division
FOR EACH STATEMENT
EXECUTE PROCEDURE refresh_autocomplete()|


CREATE TRIGGER refresh_autocomplete_trigger
AFTER INSERT OR UPDATE OR DELETE
ON offer
FOR EACH STATEMENT
EXECUTE PROCEDURE refresh_autocomplete()|

CREATE TRIGGER refresh_autocomplete_trigger
AFTER INSERT OR UPDATE OR DELETE
ON resource
FOR EACH STATEMENT
EXECUTE PROCEDURE refresh_autocomplete()|