defmodule Transport.Repo.Migrations.MoreResourceMetadata do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      add :last_update, :string
      add :latest_url, :string
    end

    alter table(:dataset) do
      add :organization, :string
    end
  end
end
