defmodule DB.Repo.Migrations.AddColumnsCommunes do
  use Ecto.Migration

  def change do
    alter table(:commune) do
      add :siren, :string
      add :population, :integer
      add :arrondissement_insee, :string
      add :departement_insee, references(:departement, column: :insee, type: :string)
      remove :wikipedia
    end

    create index(:commune, [:departement_insee])
    create unique_index(:commune, [:siren])
  end
end
