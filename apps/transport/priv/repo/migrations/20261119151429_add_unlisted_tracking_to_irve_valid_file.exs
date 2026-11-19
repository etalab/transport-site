defmodule DB.Repo.Migrations.AddUnlistedTrackingToIrveValidFile do
  use Ecto.Migration

  def change do
    alter table(:irve_valid_file) do
      add(:unlisted_since, :date)
      add(:soft_deleted_at, :utc_datetime)
    end
  end
end
