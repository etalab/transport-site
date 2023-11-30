defmodule DB.Repo.Migrations.RemoveColumnsFromAOM do
  use Ecto.Migration

  def change do
    execute("UPDATE aom SET departement = '0' || departement WHERE length(departement) = 1;", "")
    execute("UPDATE aom SET departement = '988' WHERE departement = '98';", "")
    rename(table(:aom), :population_totale, to: :population)

    alter table(:aom) do
      # CEREMA only provides one population column now
      remove(:population_municipale, :integer)
      # This column was empty in database
      remove(:commentaire, :string)
      # This column was empty in database, now we use the region relation
      remove(:region_name, :string)
      modify(:departement, references(:departement, column: :insee, type: :string), from: :string)
    end

    execute(&execute_up/0, &execute_down/0)

    # Force update
    execute("UPDATE dataset SET id = id", "")
  end

  defp execute_up do
    repo().query!(sql_dataset_update_function("population"), [], log: :info)
  end

  def execute_down do
    repo().query!(sql_dataset_update_function("population_totale"), [], log: :info)
  end

  def sql_dataset_update_function(aom_population_attribute) do
    """
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
    SELECT aom.nom, region.nom, aom.#{aom_population_attribute} INTO nom, region_nom, population
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
    SELECT region.nom, SUM(aom.#{aom_population_attribute}) INTO nom, population
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
    """
  end
end
