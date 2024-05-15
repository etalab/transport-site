defmodule DB.Repo.Migrations.AddDatasetDatagouvIdToResourceMonthlyMetrics do
  use Ecto.Migration

  def change do
    alter table(:resource_monthly_metrics) do
      # nullable for now as we might need to refresh the data in a job
      add(:dataset_datagouv_id, references(:dataset, column: :datagouv_id, type: :string))
    end
  end
end
