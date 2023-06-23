defmodule DB.Repo.Migrations.AomRemoveParentDatasetId do
  use Ecto.Migration

  def up do
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
    SELECT aom.nom, region.nom, aom.population_totale INTO nom, region_nom, population
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
    SELECT region.nom, SUM(aom.population_totale) INTO nom, population
    FROM region
    JOIN aom ON aom.region_id = region.id
    WHERE region.id = NEW.region_id
    GROUP BY region.nom;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
    NEW.population = population;

    ELSE
    SELECT coalesce(sum(c.population),0) INTO population FROM dataset_communes dc
    LEFT JOIN commune c ON c.id = dc.commune_id WHERE dc.dataset_id = NEW.id;

    NEW.population = population;
    END IF;

    IF EXISTS (
      select dataset_id
      from dataset_aom_legal_owner
      where dataset_id = NEW.id
      group by dataset_id
      having count(aom_id) >= 2
    ) THEN
    SELECT string_agg(a.nom, ' ') INTO nom
    from aom a
    left join dataset_aom_legal_owner d on d.aom_id = a.id
    where d.dataset_id = NEW.id OR a.id = NEW.aom_id;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
    END IF;

    RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION dataset_communes_update() RETURNS trigger as $$
    BEGIN

    IF NEW.dataset_id IS NOT NULL THEN
    UPDATE dataset SET id = id WHERE id = NEW.dataset_id;
    END IF;

    RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE TRIGGER dataset_communes_update
    AFTER INSERT OR UPDATE ON dataset_communes
    FOR EACH ROW
    EXECUTE PROCEDURE dataset_communes_update();
    """)

    # Force update
    execute("UPDATE dataset SET id = id")

    alter table(:aom) do
      remove :parent_dataset_id
    end
  end

  def down do
    alter table(:aom) do
      add :parent_dataset_id, references ("dataset")
    end

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
    SELECT aom.nom, region.nom, aom.population_totale INTO nom, region_nom, population
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
    SELECT region.nom, SUM(aom.population_totale) INTO nom, population
    FROM region
    JOIN aom ON aom.region_id = region.id
    WHERE region.id = NEW.region_id
    GROUP BY region.nom;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
    NEW.population = population;

    ELSE
    SELECT coalesce(sum(c.population),0) INTO population FROM dataset_communes dc
    LEFT JOIN commune c ON c.id = dc.commune_id WHERE dc.dataset_id = NEW.id;

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

    execute("""
    CREATE OR REPLACE FUNCTION dataset_communes_update() RETURNS trigger as $$
    BEGIN

    IF NEW.dataset_id IS NOT NULL THEN
    UPDATE dataset SET id = id WHERE id = NEW.dataset_id;
    END IF;

    RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE OR REPLACE TRIGGER dataset_communes_update
    AFTER INSERT OR UPDATE ON dataset_communes
    FOR EACH ROW
    EXECUTE PROCEDURE dataset_communes_update();
    """)

    # Force update
    execute("UPDATE dataset SET id = id")
  end
end
