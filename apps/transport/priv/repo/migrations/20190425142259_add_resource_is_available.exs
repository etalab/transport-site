defmodule DB.Repo.Migrations.AddResourceIsAvailable do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :is_available, :boolean, default: true
    end
  end
end
