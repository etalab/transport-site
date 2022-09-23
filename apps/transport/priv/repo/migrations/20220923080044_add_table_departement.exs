defmodule DB.Repo.Migrations.AddTableDepartement do
  use Ecto.Migration

  def change do
    drop index(:commune, [:insee])
    create unique_index(:commune, [:insee])

    create table(:departement) do
      add :insee, :string, null: false
      add :region_insee, references(:region, column: :insee, type: :string)
      add :chef_lieu, references(:commune, column: :insee, type: :string)
      add :nom, :string, null: false
      add :zone, :string, null: false
      add :geom, :geometry, null: false
    end

    create index(:departement, [:region_insee])
    create index(:departement, [:zone])
    create unique_index(:departement, [:insee])
    create unique_index(:departement, [:nom])
  end
end
