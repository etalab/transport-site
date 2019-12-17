defmodule DB.Repo.Migrations.AddResourceTags do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :auto_tags, {:array, :string}, default: []
      add :manual_tags, {:array, :string}, default: []
    end
  end
end
