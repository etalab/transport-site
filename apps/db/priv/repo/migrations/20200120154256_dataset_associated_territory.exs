defmodule DB.Repo.Migrations.DatasetAssociatedTerritory do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:associated_territory_name, :string)
    end
  end
end
