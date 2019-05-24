defmodule Transport.Repo.Migrations.RenameTransitTypes do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset set type='public-transit' where type='transport-statique'"
    execute "UPDATE dataset set type='micro-mobility' where type='bike sharing'"
    execute "UPDATE dataset set type='carsharing-areas' where type='aires-covoiturage'"
    execute "UPDATE dataset set type='charging-stations' where type='borne-recharge'"
  end

  def down do
    execute "UPDATE dataset set type='transport-statique' where type='public-transit'"
    execute "UPDATE dataset set type='bike sharing' where type='micro-mobility'"
    execute "UPDATE dataset set type='aires-covoiturage' where type='carsharing-areas'"
    execute "UPDATE dataset set type='borne-recharge' where type='charging-stations'"
  end
end
