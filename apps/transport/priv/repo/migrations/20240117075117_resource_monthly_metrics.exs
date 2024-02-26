defmodule DB.Repo.Migrations.ResourceMonthlyMetrics do
  use Ecto.Migration

  def change do
    create table(:resource_monthly_metrics) do
      add(:resource_datagouv_id, :string, null: false, size: 50)
      # Example: 2023-12
      add(:year_month, :string, null: false, size: 7)
      add(:metric_name, :string, null: false, size: 50)
      add(:count, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:resource_monthly_metrics, [:resource_datagouv_id, :year_month, :metric_name]))
  end
end
