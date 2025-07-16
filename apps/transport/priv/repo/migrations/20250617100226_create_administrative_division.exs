defmodule DB.Repo.Migrations.CreateAdministrativeDivision do
  use Ecto.Migration

  def change do
    create table(:administrative_division) do
      add(:type_insee, :string, null: false)
      add(:type, :string, null: false)
      add(:insee, :string, null: false)
      add(:nom, :string, null: false)
      add(:geom, :geometry, null: false)

      # NOTE: this table doesn’t show relationships between divisions,
      # such as communes belonging to an EPCI and a departement, etc.
    end

    create(unique_index(:administrative_division, [:type_insee]))
    create(index(:administrative_division, [:nom]))

    # NOTE: To populate this table, run: mix Transport.PopulateAdministrativeDivisions
  end
end
