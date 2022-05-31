defmodule DB.Repo.Migrations.ModifyResourceHistoryConstraint do
  use Ecto.Migration

def change do
  alter table(:resource_history) do
    modify :resource_id, references(:resource, on_delete: :nilify_all),
      from: references(:resource, on_delete: :nothing)
  end
end
end
