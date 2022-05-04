defmodule DB.Repo.Migrations.MoveMetadata do
  use Ecto.Migration

  def up do
    alter table(:dataset) do
      remove :metadata
    end

    alter table(:resource) do
      add :metadata, :map
    end
  end

  def down do
    alter table(:resource) do
      remove :metadata
    end

    alter table(:dataset) do
      add :metadata, :map
    end
  end
end
