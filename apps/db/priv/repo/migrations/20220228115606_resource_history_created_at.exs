defmodule DB.Repo.Migrations.ResourceHistoryCreatedAt do
  use Ecto.Migration

  def change do
    alter table(:resource_history) do
      add(:created_at, :utc_datetime_usec)
    end
  end
end
