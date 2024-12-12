defmodule DB.Repo.Migrations.AddDatasetTerritoriesTable do
  use Ecto.Migration

  def change do
    create table("dataset_territories", primary_key: false) do
        add(:dataset_id, references(:dataset), on_delete: :delete_all, null: false)
        add(:territory_type, :string, null: false) # This cannot be null
        # For the following fields, it’s only one of them that needs to be filled
        # Idealy should be consistent with territory type
        add(:commune_id, references(:commune), on_delete: :delete_all)
        add(:departement_id, references(:departement), on_delete: :delete_all)
        add(:epci_id, references(:epci), on_delete: :delete_all)
        add(:region_id, references(:region), on_delete: :delete_all)

      timestamps()
    end
  end
end
