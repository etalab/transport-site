defmodule DB.Repo.Migrations.DisableDatasetGeographicViewTrigger do
  use Ecto.Migration

  def change do
    execute("ALTER TABLE dataset DISABLE TRIGGER refresh_dataset_geographic_view_trigger")
  end
end
