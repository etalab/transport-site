defmodule DB.Repo.Migrations.CreateRegion do
  use Ecto.Migration

  def change do
    create table(:region) do
      add :nom, :string
      add :insee, :string
      add :geometry, :map
      add :is_completed, :boolean
    end
  end
end
