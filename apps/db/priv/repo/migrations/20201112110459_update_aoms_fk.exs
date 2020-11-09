defmodule DB.Repo.Migrations.UpdateAomsFk do
  use Ecto.Migration

  def up do
    # Add an update cascade to the foreign key for an aom composition_res_id change to be propagated
    # Note: it is not support by ecto
    execute("""
    ALTER TABLE commune
    DROP CONSTRAINT commune_aom_res_id_fkey,
    ADD CONSTRAINT commune_aom_res_id_fkey
    FOREIGN KEY (aom_res_id)
    REFERENCES aom(composition_res_id)
    ON UPDATE CASCADE;
    """)
  end
  def down do
    execute("""
    ALTER TABLE commune
    DROP CONSTRAINT commune_aom_res_id_fkey,
    ADD CONSTRAINT commune_aom_res_id_fkey
    FOREIGN KEY (aom_res_id)
    REFERENCES aom(composition_res_id);
    """)
  end
end
