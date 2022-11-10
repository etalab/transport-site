defmodule DB.Repo.Migrations.RenameMobilityLicense do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset SET licence = 'mobility-licence' WHERE licence = 'mobility-license'"
  end

  def down do
    execute "UPDATE dataset SET licence = 'mobility-license' WHERE licence = 'mobility-licence'"
  end
end
