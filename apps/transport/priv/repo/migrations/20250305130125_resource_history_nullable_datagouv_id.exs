defmodule DB.Repo.Migrations.ResourceHistoryNullableDatagouvId do
  use Ecto.Migration

  def change do
    alter table(:resource_history) do
      modify :datagouv_id, :string, null: true, from: :string
    end
  end
end
