defmodule DB.Repo.Migrations.GeoDataImportAddSlug do
  use Ecto.Migration

  def change do
    alter table(:geo_data_import) do
      add(:slug, :string)
    end

    create(unique_index(:geo_data_import, [:slug]))
  end
end
