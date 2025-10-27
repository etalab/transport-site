defmodule DB.Repo.Migrations.CommuneAomSiren do
  use Ecto.Migration

  def change do
    alter table(:commune) do
      add(:aom_siren, :varchar, null: true)
    end

    execute(
      """
      UPDATE commune SET aom_siren = t.siren
      FROM (
      SELECT composition_res_id, siren
      FROM aom
      ) t
      WHERE t.composition_res_id = commune.aom_res_id;
      """,
      ""
      )

    execute("""
      CREATE OR REPLACE FUNCTION dataset_search_update() RETURNS trigger as $$
      DECLARE
      nom text;
      region_nom region.nom%TYPE;
      BEGIN

      NEW.search_vector = setweight(to_tsvector('custom_french', coalesce(NEW.custom_title, '')), 'B') ||
      setweight(to_tsvector('custom_french', array_to_string(NEW.tags, ',')), 'C') ||
      setweight(to_tsvector('custom_french', coalesce(NEW.description, '')), 'D');

      IF NEW.aom_id IS NOT NULL THEN
      SELECT aom.nom, region.nom INTO nom, region_nom
      FROM aom
      JOIN region ON region.id = aom.region_id
      WHERE aom.id = NEW.aom_id;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A') ||
      setweight(to_tsvector('custom_french', coalesce(region_nom, '')), 'B');

      SELECT string_agg(commune.nom, ' ') INTO nom
      FROM commune
      JOIN aom ON aom.siren = commune.aom_siren
      WHERE aom.id = NEW.aom_id;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'B');

      ELSIF NEW.region_id IS NOT NULL THEN
      SELECT region.nom INTO nom
      FROM region
      JOIN aom ON aom.region_id = region.id
      WHERE region.id = NEW.region_id
      GROUP BY region.nom;

      NEW.search_vector = NEW.search_vector ||
      setweight(to_tsvector('custom_french', coalesce(nom, '')), 'A');
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

    alter table(:commune) do
      remove(:aom_res_id)
    end
  end
end
