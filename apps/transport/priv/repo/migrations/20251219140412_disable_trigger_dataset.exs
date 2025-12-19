defmodule DB.Repo.Migrations.DisableTriggerDataset do
  use Ecto.Migration

  def change do
    if Mix.env() == :test do
      execute("ALTER TABLE dataset DISABLE TRIGGER dataset_update_trigger")
    end
  end
end
