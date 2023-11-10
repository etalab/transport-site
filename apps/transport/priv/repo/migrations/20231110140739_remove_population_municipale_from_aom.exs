defmodule DB.Repo.Migrations.RemovePopulationMunicipaleFromAOM do
  use Ecto.Migration

  def change do
    alter table(:aom) do
      remove :population_municipale, :integer # CEREMA only provides one population column now
      remove :commentaire, :string # This column was empty in database
    end
    rename table(:aom), :population_totale, to: :population
  end
end
