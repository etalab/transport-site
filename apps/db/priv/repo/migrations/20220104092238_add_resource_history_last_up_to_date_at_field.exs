defmodule DB.Repo.Migrations.AddResourceHistoryLastUpToDateAtField do
  use Ecto.Migration

  def change do
    alter table(:resource_history) do
      add(:last_up_to_date_at, :utc_datetime_usec)
    end
  end
end
