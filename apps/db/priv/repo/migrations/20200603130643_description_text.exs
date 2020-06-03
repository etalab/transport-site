defmodule DB.Repo.Migrations.DescriptionText do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      modify :description, :text
    end
  end
end
