defmodule DB.Repo.Migrations.AddDatagouvIdToDatasetHistoryResources do
  use Ecto.Migration

  def change do
    alter table(:dataset_history_resources) do
      add(:resource_datagouv_id, :string)
    end
  end
end
