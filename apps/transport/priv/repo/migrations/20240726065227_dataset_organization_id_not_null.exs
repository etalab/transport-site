defmodule DB.Repo.Migrations.DatasetOrganizationIdNotNull do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE dataset ALTER COLUMN organization_id SET NOT NULL")
  end

  def down do
    execute("ALTER TABLE dataset ALTER COLUMN organization_id DROP NOT NULL")
  end
end
