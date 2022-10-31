defmodule DB.Repo.Migrations.DatasetAddTimestamps do
  use Ecto.Migration

  def change do
    alter table(:dataset) do
      timestamps(type: :utc_datetime_usec, null: true)
    end
  end
end
