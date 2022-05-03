defmodule DB.Repo.Migrations.CommunautaryResources do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :is_community_resource, :boolean
      add :description, :string
      add :community_resource_publisher, :string
    end
  end
end
