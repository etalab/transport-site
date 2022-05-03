defmodule DB.Repo.Migrations.NetexConverionDate do
  use Ecto.Migration

  def change do
      alter table(:resource) do
        add :netex_conversion_latest_content_hash, :string
      end
  end
end
