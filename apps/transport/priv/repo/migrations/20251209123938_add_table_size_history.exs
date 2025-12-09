defmodule DB.Repo.Migrations.AddTableSizeHistory do
  use Ecto.Migration

  def change do
    create table(:table_size_history) do
      add(:table_name, :string, null: false)
      add(:size, :bigint, null: false)
      add(:date, :date, null: false)
    end

    create(index(:table_size_history, [:table_name]))
    create(unique_index(:table_size_history, [:table_name, :date]))
  end
end
