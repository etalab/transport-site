defmodule DB.Repo.Migrations.MorePt do
  use Ecto.Migration

  def change do
    execute("UPDATE dataset SET type = 'public-transit' where type = 'long-distance-coach' or type = 'train';")
  end
end
