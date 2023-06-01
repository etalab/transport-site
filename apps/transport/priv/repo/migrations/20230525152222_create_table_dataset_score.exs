defmodule DB.Repo.Migrations.CreateTableDatasetScore do
  use Ecto.Migration

  def change do
    create table(:dataset_score) do
      add :dataset_id, references(:dataset, on_delete: :delete_all)
      add :topic, :string
      add :score, :float
      add :timestamp, :utc_datetime_usec
      add :details, :jsonb
    end

    create index("dataset_score", [:dataset_id])
  end
end
