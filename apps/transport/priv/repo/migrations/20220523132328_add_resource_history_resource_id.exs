defmodule DB.Repo.Migrations.AddResourceHistoryResourceId do
  use Ecto.Migration

  def change do
    alter table(:resource_history) do
      add :resource_id, references(:resource)
    end
  end
end
