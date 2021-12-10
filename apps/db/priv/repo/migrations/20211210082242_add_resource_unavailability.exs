defmodule DB.Repo.Migrations.AddResourceUnavailability do
  use Ecto.Migration

  def change do
    create table(:resource_unavailability) do
      add :resource_id, references(:resource), null: false
      add :start,:utc_datetime, null: false
      add :end,:utc_datetime
      timestamps([type: :utc_datetime_usec])
    end

    create index(:resource_unavailability, [:resource_id])
  end
end
