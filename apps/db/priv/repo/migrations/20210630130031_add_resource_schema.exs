defmodule DB.Repo.Migrations.AddResourceSchema do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :schema_name, :string
      add :schema_version, :string
    end
  end
end
