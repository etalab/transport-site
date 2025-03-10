defmodule DB.Repo.Migrations.ResourceHistoryAddReuserImprovedData do
  use Ecto.Migration

  def change do
    alter table(:resource_history) do
      add(:reuser_improved_data_id, references(:reuser_improved_data, on_delete: :delete_all))
    end
  end
end
