defmodule DB.Repo.Migrations.AddResourceType do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :type, :string
    end
  end
end
