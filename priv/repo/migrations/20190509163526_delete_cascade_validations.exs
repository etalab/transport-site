defmodule Transport.Repo.Migrations.DeleteCascadeValidations do
  use Ecto.Migration

  def change do
    drop constraint(:validations, "validations_resource_id_fkey")
    alter table(:validations) do
        modify :resource_id, references(:resource, on_delete: :delete_all)
    end
  end
end
