defmodule DB.Repo.Migrations.DatasetAddArchivedAtField do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      add(:archived_at, :utc_datetime_usec)
    end
  end
end
