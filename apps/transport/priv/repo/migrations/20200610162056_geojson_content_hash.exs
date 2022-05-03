defmodule DB.Repo.Migrations.GeojsonContentHash do
  use Ecto.Migration

  def change do
    rename table(:resource), :netex_conversion_latest_content_hash, to: :conversion_latest_content_hash
  end
end
