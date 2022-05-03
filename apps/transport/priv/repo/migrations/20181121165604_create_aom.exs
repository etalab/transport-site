defmodule DB.Repo.Migrations.CreateAom do
  use Ecto.Migration

  def change do
    create table(:aom) do
      add :composition_res_id, :integer
      add :insee_commune_principale, :string
      add :region_name, :string
      add :departement, :string
      add :siren, :integer
      add :nom, :string
      add :forme_juridique, :string
      add :nombre_communes, :integer
      add :population_muni_2014, :integer
      add :population_totale_2014, :integer
      add :surface, :string
      add :commentaire, :string
      add :geometry, :map

      add :region_id, references(:region)
    end
  end
end
