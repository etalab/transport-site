defmodule DB.Repo.Migrations.DatasetMonthlyMetrics do
  use Ecto.Migration

  def change do
    create table(:dataset_monthly_metrics) do
      add(:dataset_datagouv_id, references(:dataset, column: :datagouv_id, type: :string, on_delete: :delete_all),
        null: false
      )

      add(:year_month, :string, null: false)
      add(:metric_name, :string, null: false)
      add(:count, :integer, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:dataset_monthly_metrics, [:dataset_datagouv_id, :year_month, :metric_name]))
  end
end
