defmodule DB.Repo.Migrations.OriginalResourceUrl do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:original_resource_url, :string)
    end
  end
end
