defmodule DB.Repo.Migrations.RenameCategoryBikePath do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset set type='bike-way' where type='bike-path'"
  end

  def down do
    execute "UPDATE dataset set type='bike-path' where type='bike-way'"
  end
end
