defmodule DB.Repo.Migrations.DatasetAddOrganizationId do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add :organization_id, :string, null: true
    end
    create_if_not_exists(index(:dataset, [:organization_id]))
  end
end
