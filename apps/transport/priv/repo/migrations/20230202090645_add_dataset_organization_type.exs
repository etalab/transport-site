defmodule DB.Repo.Migrations.AddDatasetOrganizationType do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add :organization_type, :string
    end
  end
end
