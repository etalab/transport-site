defmodule Transport.Repo.Migrations.AddDatasetDocument do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add :search_vector, :tsvector
      add :population, :integer
    end

    create_if_not_exists index(:dataset, [:search_vector], using: "GIN")

    execute("""
        CREATE OR REPLACE FUNCTION dataset_search_update() RETURNS trigger as $$
        DECLARE
          nom text;
          region_nom region.nom%TYPE;
          population dataset.population%TYPE;
        BEGIN

        NEW.search_vector = setweight(to_tsvector(coalesce(NEW.spatial, '')), 'B') ||
              setweight(to_tsvector(array_to_string(NEW.tags, ',')), 'C') ||
              setweight(to_tsvector(coalesce(NEW.description, '')), 'D');

        IF NEW.aom_id IS NOT NULL THEN
          SELECT aom.nom, region.nom, aom.population_totale_2014 INTO nom, region_nom, population
          FROM aom
          JOIN region ON region.id = aom.region_id
          WHERE aom.id = NEW.aom_id;

          NEW.search_vector = NEW.search_vector ||
            setweight(to_tsvector(coalesce(nom, '')), 'A') ||
            setweight(to_tsvector(coalesce(region_nom, '')), 'B');
          NEW.population = population;

        ELSIF NEW.region_id IS NOT NULL THEN
          SELECT region.nom, SUM(aom.population_totale_2014) INTO nom, population
          FROM region
          JOIN aom ON aom.region_id = region.id
          WHERE region.id = NEW.region_id
          GROUP BY region.nom;

          NEW.search_vector = NEW.search_vector ||
            setweight(to_tsvector(coalesce(nom, '')), 'A');
          NEW.population = population;
        END IF;

        IF EXISTS (SELECT 1 FROM aom WHERE parent_dataset_id = NEW.id) THEN
          SELECT string_agg(aom.nom, ' ') INTO nom FROM aom WHERE parent_dataset_id = NEW.id;

          NEW.search_vector = NEW.search_vector ||
            setweight(to_tsvector(coalesce(nom, '')), 'A');
        END IF;

        RETURN NEW;
        END
        $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS dataset_search_update;")

    execute("""
        CREATE TRIGGER dataset_update_trigger
        BEFORE INSERT OR UPDATE ON dataset
        FOR EACH ROW
        EXECUTE PROCEDURE dataset_search_update();
    """,
    "DROP TRIGGER IF EXISTS dataset_update_trigger ON dataset;")

    # Force update
    execute("UPDATE dataset SET id = id", "")

    # Trigger for aom and region update
    execute("""
      CREATE OR REPLACE FUNCTION aom_update() RETURNS trigger as $$
      DECLARE
        dataset_id dataset.id%TYPE;
      BEGIN
      SELECT dataset.id INTO dataset_id FROM dataset WHERE aom_id = NEW.id;

      IF dataset_id IS NOT NULL THEN
        UPDATE dataset SET id = id WHERE id = dataset_id;
      END IF;

      RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS aom_update;")

    execute("""
    CREATE TRIGGER aom_update_trigger
    AFTER INSERT OR UPDATE ON aom
    FOR EACH ROW
    EXECUTE PROCEDURE aom_update();
    """,
    "DROP TRIGGER IF EXISTS aom_update_trigger ON aom;")

    execute("""
      CREATE OR REPLACE FUNCTION region_update() RETURNS trigger as $$
      DECLARE
        dataset_id dataset.id%TYPE;
      BEGIN
      SELECT dataset.id INTO dataset_id FROM dataset WHERE region_id = NEW.id;

      IF dataset_id IS NOT NULL THEN
        UPDATE dataset SET id = id WHERE id = dataset_id;
      END IF;

      RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
    """,
    "DROP FUNCTION IF EXISTS region_update;")

    execute("""
    CREATE TRIGGER region_update_trigger
    AFTER INSERT OR UPDATE ON region
    FOR EACH ROW
    EXECUTE PROCEDURE region_update();
    """,
    "DROP TRIGGER IF EXISTS region_update_trigger ON region;")
  end
end
