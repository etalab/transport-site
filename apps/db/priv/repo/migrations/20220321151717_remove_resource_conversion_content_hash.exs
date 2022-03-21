defmodule DB.Repo.Migrations.RemoveResourceConversionContentHash do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      remove :conversion_latest_content_hash, :string, default: ""
    end
  end
end
