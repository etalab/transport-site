defmodule DB.Repo.Migrations.AddMissingFieldsToIrveValidFile do
  use Ecto.Migration

  def change do
    alter table(:irve_valid_file) do
      add(:dataset_title, :string)
      add(:datagouv_organization_or_owner, :string)
      add(:datagouv_last_modified, :utc_datetime)
    end
  end
end
