defmodule DB.Repo.Migrations.ResourceLogValidation do
  use Ecto.Migration

  def change do
    # droping the constraint because it will be readed by the modification of the field
    drop constraint(:logs_validation, "logs_validation_resource_id_fkey")
    alter table(:logs_validation) do
      modify(:resource_id, references(:resource, on_delete: :delete_all))
    end
    drop constraint(:logs_import, "logs_import_dataset_id_fkey")
    alter table(:logs_import) do
      modify(:dataset_id, references(:dataset, on_delete: :delete_all))
    end
  end
end
