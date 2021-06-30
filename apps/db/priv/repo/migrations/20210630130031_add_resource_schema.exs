defmodule DB.Repo.Migrations.AddResourceSchema do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :schema, :string
    end
  end
end
