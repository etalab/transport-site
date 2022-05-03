defmodule DB.Repo.Migrations.AddResourceFilesize do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add(:filesize, :integer)
    end
  end
end
