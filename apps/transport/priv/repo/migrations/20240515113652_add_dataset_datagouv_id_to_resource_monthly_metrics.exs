defmodule DB.Repo.Migrations.AddDatasetDatagouvIdToResourceMonthlyMetrics do
  use Ecto.Migration

  def change do
    alter table(:resource_monthly_metrics) do
      # nullable for now as we might need to refresh the data in a job
      add(:dataset_datagouv_id, references(:dataset, column: :datagouv_id))
    end

    # FIXME redefine the unique_index with something like this?:
    # create(unique_index(:resource_monthly_metrics, [:resource_datagouv_id, :dataset_datagouv_id, :year_month, :metric_name]))
  end
end
