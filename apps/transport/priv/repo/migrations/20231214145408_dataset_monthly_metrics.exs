defmodule DB.Repo.Migrations.DatasetMonthlyMetrics do
  use Ecto.Migration

  def change do
    create table(:dataset_monthly_metrics) do
      # Not adding a foreign key: https://github.com/etalab/transport-site/pull/3663/files#r1429890393
      add(:dataset_datagouv_id, :string, null: false, size: 50)
      # Example: 2023-12
      add(:year_month, :string, null: false, size: 7)
      add(:metric_name, :string, null: false, size: 50)
      add(:count, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:dataset_monthly_metrics, [:dataset_datagouv_id, :year_month, :metric_name]))
  end
end
