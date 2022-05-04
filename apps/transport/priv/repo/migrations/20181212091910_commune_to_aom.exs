defmodule DB.Repo.Migrations.CommuneToAom do
  use Ecto.Migration

  def up do
    create unique_index(:aom, [:composition_res_id])

    alter table(:commune) do
      add :aom_res_id, references(:aom, column: :composition_res_id)
    end

    # flush()
    # Mix.Task.run("DB.import_aom", [no_start: true])
    # Mix.Task.run("DB.import_insee_aom", [no_start: true])
  end

  def down do
    drop constraint(:commune, "commune_aom_res_id_fkey")
    drop index(:aom, [:composition_res_id])
    alter table(:commune) do
      remove :aom_res_id
    end
  end
end
