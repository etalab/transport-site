defmodule Elixir.DB.Repo.Migrations.DatasetNewCoveredArea do
  use Ecto.Migration

  def change do
    create table("dataset_new_covered_area", primary_key: false) do
      add(:dataset_id, references(:dataset), on_delete: :delete_all, null: false)
      # This cannot be null
      add(:administrative_division_type, :string, null: false)
      # For the following fields, it’s only one of them that needs to be filled
      # Idealy should be consistent with territory type
      add(:commune_id, references(:commune), on_delete: :delete_all)
      add(:departement_id, references(:departement), on_delete: :delete_all)
      add(:epci_id, references(:epci), on_delete: :delete_all)
      add(:region_id, references(:region), on_delete: :delete_all)

      timestamps()
    end

    execute(
      """
        ALTER TABLE dataset_new_covered_area
        ADD CONSTRAINT single_required_administrative_division
        CHECK (num_nonnulls(commune_id, departement_id, epci_id, region_id) = 1)
      """,
      ""
    )
  end
end
