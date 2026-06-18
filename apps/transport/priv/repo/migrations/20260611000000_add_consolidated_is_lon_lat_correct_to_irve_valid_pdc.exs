defmodule Transport.Repo.Migrations.AddConsolidatedIsLonLatCorrectToIrveValidPdc do
  use Ecto.Migration

  def change do
    alter table(:irve_valid_pdc) do
      add(:consolidated_is_lon_lat_correct, :boolean, null: false, default: false)
    end
  end
end
