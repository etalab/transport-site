defmodule DB.Repo.Migrations.RemoveResourceStartEndDate do
  use Ecto.Migration

  def change do
    alter table(:resource) do
      remove(:start_date, :date)
      remove(:end_date, :date)
    end
  end
end
