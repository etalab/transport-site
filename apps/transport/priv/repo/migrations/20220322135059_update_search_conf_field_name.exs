defmodule DB.Repo.Migrations.UpdateSearchConfFieldName do
    use Ecto.Migration

    def up do
      # same function as before, but spatial columns becomes custom_title
      execute("""
      CREATE OR REPLACE FUNCTION dataset_search_update() RETURNS trigger as $$
      DECLARE
      nom text;
      region_nom region.nom%TYPE;
      population dataset.population%TYPE;
      BEGIN

      NEW.search_vector = setweight(to_tsvector('custom_french', coalesce(NEW.custom_title, '')), 'B') ||
      setweight(to_tsvector('custom_french', array_to_string(NEW.tags, ',')), 'C') ||
      setweight(to_tsvector('custom_french', coalesce(NEW.description, '')), 'D');

      IF NEW.aom_id IS NOT NULL THEN
      SELECT aom.nom, region.nom, aom.population_totale_2014 INTO nom, region_nom, population
      FROM aom
      JOIN region ON region.id = aom.region_id
      WHERE aom.id = NEW.aom_id;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A') ||
      setweight(to_tsvector('custom_french', coalesce(region_nom, '')), 'B');
      NEW.population = population;

      SELECT string_agg(commune.nom, ' ') INTO nom
      FROM commune
      JOIN aom ON aom.composition_res_id = commune.aom_res_id
      WHERE aom.id = NEW.aom_id;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'B');

      ELSIF NEW.region_id IS NOT NULL THEN
      SELECT region.nom, SUM(aom.population_totale_2014) INTO nom, population
      FROM region
      JOIN aom ON aom.region_id = region.id
      WHERE region.id = NEW.region_id
      GROUP BY region.nom;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
      NEW.population = population;
      END IF;

      IF EXISTS (SELECT 1 FROM aom WHERE parent_dataset_id = NEW.id) THEN
      SELECT string_agg(aom.nom, ' ') INTO nom FROM aom WHERE parent_dataset_id = NEW.id;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
      END IF;

      RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
      """)

      # Force update
      execute("UPDATE dataset SET id = id", "")
    end

    def down do
    # previous function definition, using "spatial" column
   execute("""
    CREATE OR REPLACE FUNCTION dataset_search_update() RETURNS trigger as $$
    DECLARE
    nom text;
    region_nom region.nom%TYPE;
    population dataset.population%TYPE;
    BEGIN

    NEW.search_vector = setweight(to_tsvector('custom_french', coalesce(NEW.spatial, '')), 'B') ||
    setweight(to_tsvector('custom_french', array_to_string(NEW.tags, ',')), 'C') ||
    setweight(to_tsvector('custom_french', coalesce(NEW.description, '')), 'D');

    IF NEW.aom_id IS NOT NULL THEN
    SELECT aom.nom, region.nom, aom.population_totale_2014 INTO nom, region_nom, population
    FROM aom
    JOIN region ON region.id = aom.region_id
    WHERE aom.id = NEW.aom_id;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A') ||
    setweight(to_tsvector('custom_french', coalesce(region_nom, '')), 'B');
    NEW.population = population;

    SELECT string_agg(commune.nom, ' ') INTO nom
    FROM commune
    JOIN aom ON aom.composition_res_id = commune.aom_res_id
    WHERE aom.id = NEW.aom_id;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'B');

    ELSIF NEW.region_id IS NOT NULL THEN
    SELECT region.nom, SUM(aom.population_totale_2014) INTO nom, population
    FROM region
    JOIN aom ON aom.region_id = region.id
    WHERE region.id = NEW.region_id
    GROUP BY region.nom;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
    NEW.population = population;
    END IF;

    IF EXISTS (SELECT 1 FROM aom WHERE parent_dataset_id = NEW.id) THEN
    SELECT string_agg(aom.nom, ' ') INTO nom FROM aom WHERE parent_dataset_id = NEW.id;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
    END IF;

    RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """)

      # Force update
      execute("UPDATE dataset SET id = id", "")
    end
end
