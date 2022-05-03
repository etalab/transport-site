defmodule :"Elixir.DB.Repo.Migrations.Rename-category-bike-scooter-sharing" do
  use Ecto.Migration

  def up do
    execute "UPDATE dataset set type='bike-scooter-sharing' where type='bike-sharing'"
  end

  def down do
    execute "UPDATE dataset set type='bike-sharing' where type='bike-scooter-sharing'"
  end
end
