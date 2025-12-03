defmodule DB.Repo.Migrations.AddIndexesResourceHistory do
  use Ecto.Migration

  def change do
    # Fix de performance pour /api/datasets, nécessaire pour ne pas utiliser
    # l‘index suivant qui dégrade les performances
    create_if_not_exists(index(:resource_history, [:resource_id, :inserted_at]))

    # Fix de performance pour datasets#details
    create_if_not_exists(index(:resource_history, [:inserted_at]))
  end
end
