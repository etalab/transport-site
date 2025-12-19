defmodule DB.Repo.Migrations.DisableTriggerDataset do
  use Ecto.Migration

  def change do
    if Mix.env() == :test do
      execute("ALTER TABLE dataset DISABLE TRIGGER dataset_update_trigger")
      execute("ALTER TABLE dataset DISABLE TRIGGER refresh_dataset_geographic_view_trigger")
    end
  end
end
