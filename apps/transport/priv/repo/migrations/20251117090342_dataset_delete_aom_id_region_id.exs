defmodule DB.Repo.Migrations.DatasetDeleteAomIdRegionId do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      remove(:aom_id)
      remove(:region_id)
    end

    execute("""
    CREATE OR REPLACE FUNCTION dataset_search_update() RETURNS trigger as $$
    DECLARE
    nom text;
    BEGIN

    NEW.search_vector = setweight(to_tsvector('custom_french', coalesce(NEW.custom_title, '')), 'B') ||
    setweight(to_tsvector('custom_french', array_to_string(NEW.tags, ',')), 'C') ||
    setweight(to_tsvector('custom_french', coalesce(NEW.description, '')), 'D');

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
    where d.dataset_id = NEW.id;

    NEW.search_vector = NEW.search_vector ||
    setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
    END IF;

    RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """)

    execute("DROP TRIGGER IF EXISTS region_update_trigger ON region;")
    execute("DROP TRIGGER IF EXISTS aom_update_trigger ON aom;")
  end
end
