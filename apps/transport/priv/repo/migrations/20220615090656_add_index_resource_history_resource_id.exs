defmodule DB.Repo.Migrations.AddIndexResourceHistoryResourceId do
  use Ecto.Migration

  def change do
    create(index(:resource_history, [:resource_id]))
  end
end
