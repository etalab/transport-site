defmodule DB.Repo.Migrations.DepartementIso3166 do
  use Ecto.Migration

  def change do
    alter table(:departement) do
      add(:iso3166, :string)
    end

    execute("""
    UPDATE departement SET iso3166 = 'FR-' || insee;
    """)
  end
end
