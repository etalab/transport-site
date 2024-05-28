defmodule DB.Repo.Migrations.AddSearchPointsToResource do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:search_points, :geometry)
    end

    execute("CREATE INDEX resource_search_points_index ON resource USING GIST (search_points)")
  end
end
