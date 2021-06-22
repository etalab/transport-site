defmodule DB.Repo.Migrations.CharsharingToCarpooling do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset set type='carpooling-areas' where type='carsharing-areas'"
  end

  def down do
    execute "UPDATE dataset set type='carsharing-areas' where type='carpooling-areas'"
  end
end
