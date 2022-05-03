defmodule DB.Repo.Migrations.AddCategoryLocations do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset set type='locations' where type in ('stops-ref', 'addresses')"
  end

  def down do
    IO.puts("no going back")
  end
end
