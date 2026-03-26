defmodule DB.Repo.Migrations.RenameIrveValidFileColumns do
  use Ecto.Migration

  def change do
    # Rename columns to use consistent naming convention
    rename(table(:irve_valid_file), :dataset_datagouv_id, to: :datagouv_dataset_id)
    rename(table(:irve_valid_file), :resource_datagouv_id, to: :datagouv_resource_id)

    # Update the unique index to use the new column name
    rename(
      index(:irve_valid_file, [:datagouv_resource_id, :checksum],
        name: "irve_valid_file_resource_datagouv_id_checksum_index"
      ),
      to: "irve_valid_file_datagouv_resource_id_checksum_index"
    )
  end
end
