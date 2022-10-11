defmodule DB.Repo.Migrations.AddMetadataModesFeatures do
  use Ecto.Migration

  def change do
    alter table(:resource_metadata) do
      add(:features, {:array, :string}, default: [])
      add(:modes, {:array, :string}, default: [])
    end
  end
end
