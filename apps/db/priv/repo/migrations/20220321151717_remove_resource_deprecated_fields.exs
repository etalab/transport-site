defmodule DB.Repo.Migrations.RemoveResourceDeprecatedFields do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      remove :conversion_latest_content_hash, :string, default: ""
      remove :is_active, :boolean
    end
  end
end
