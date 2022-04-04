defmodule DB.Repo.Migrations.RemoveRegionDatasetAom do
  use Ecto.Migration

  def up do
    execute """
      INSERT INTO region (nom) VALUES ('National')
    """

    execute """
        UPDATE dataset
        SET region_id = (SELECT id FROM region WHERE nom = 'National')
        WHERE aom_id IS NOT NULL
    """
  end

  def down do
    execute """
      UPDATE dataset
      SET region_id = (SELECT region_id FROM aom WHERE id=dataset.aom_id)
      WHERE aom_id IS NOT NULL
    """

    execute """
      UPDATE dataset
      SET region_id = NULL
      WHERE region_id = (SELECT id FROM region WHERE nom='National')
    """

    execute """
      DELETE FROM region WHERE id = (SELECT id FROM region WHERE nom='National')
    """
  end
end
