defmodule DB.Repo.Migrations.RenameCategoryRoadNetwork do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset set type='road-data' where type='road-network'"
  end

  def down do
    execute "UPDATE dataset set type='road-network' where type='road-data'"
  end
end
