defmodule Transport.Repo.Migrations.RemoveRegionDatasetAom do
  use Ecto.Migration

  def change do
    execute """
        UPDATE dataset
        SET region_id = NULL
        WHERE aom_id IS NOT NULL
    """
  end
end
