defmodule DB.Repo.Migrations.RenameIrveValidFileColumns do
  use Ecto.Migration

  def change do
    # Rename columns to use consistent naming convention
    rename(table(:irve_valid_file), :dataset_datagouv_id, to: :datagouv_dataset_id)
    rename(table(:irve_valid_file), :resource_datagouv_id, to: :datagouv_resource_id)

    # Update the unique index to use the new column name
    drop(unique_index(:irve_valid_file, [:resource_datagouv_id, :checksum]))
    create(unique_index(:irve_valid_file, [:datagouv_resource_id, :checksum]))
  end
end
