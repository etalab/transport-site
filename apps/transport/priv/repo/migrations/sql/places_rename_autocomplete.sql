ALTER MATERIALIZED VIEW places RENAME TO autocomplete|

DROP TRIGGER IF EXISTS refresh_places_trigger ON administrative_division|
DROP TRIGGER IF EXISTS refresh_places_trigger ON offer|

DROP FUNCTION refresh_places|


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