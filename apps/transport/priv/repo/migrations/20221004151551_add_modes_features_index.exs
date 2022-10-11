defmodule DB.Repo.Migrations.AddModesFeaturesIndex do
  use Ecto.Migration

  def features_index, do: "resource_metadata_features_idx"
  def modes_index, do: "resource_metadata_modes_idx"

  def up do
    execute "create index #{features_index()} on resource_metadata using GIN (features)"
    execute "create index #{modes_index()} on resource_metadata using GIN (modes)"
  end

  def down do
    execute "drop index #{features_index()}"
    execute "drop index #{modes_index()}"
  end
end
