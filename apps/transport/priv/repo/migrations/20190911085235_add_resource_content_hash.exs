defmodule Transport.Repo.Migrations.AddResourceSha do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :content_hash, :string
    end
  end
end
