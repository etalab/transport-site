defmodule DB.Repo.Migrations.DatasetOrganizationTypeMigrateValue do
  use Ecto.Migration

  def up do
    execute("UPDATE dataset SET organization_type = 'Partenariat régional' WHERE organization_type = 'Syndicat Mixte'")
  end

  def down do
    execute("UPDATE dataset SET organization_type = 'Syndicat Mixte' WHERE organization_type = 'Partenariat régional'")
  end
end
