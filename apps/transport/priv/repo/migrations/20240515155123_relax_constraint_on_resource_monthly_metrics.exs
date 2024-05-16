defmodule DB.Repo.Migrations.RelaxConstraintOnResourceMonthlyMetrics do
  use Ecto.Migration

  def up do
    drop(constraint(:resource_monthly_metrics, "resource_monthly_metrics_dataset_datagouv_id_fkey"))
  end

  def down do
    alter table(:resource_monthly_metrics) do
      modify(:dataset_datagouv_id, references(:dataset, column: :datagouv_id, type: :string, on_delete: :delete_all))
    end
  end
end
