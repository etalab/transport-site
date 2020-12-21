defmodule DB.Repo.Migrations.StatsHistory do
  use Ecto.Migration

  def change do
    create table(:stats_history) do
      add(:timestamp, :utc_datetime)
      add(:metric, :string)
      add(:value, :decimal)
    end
    create(index(:stats_history, [:timestamp, :metric]))
  end
end
