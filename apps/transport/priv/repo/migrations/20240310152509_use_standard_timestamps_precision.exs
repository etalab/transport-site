defmodule DB.Repo.Migrations.UseStandardTimestampsPrecision do
  use Ecto.Migration

  def change do
    alter table(:processing_reports) do
      remove(:inserted_at)
      remove(:updated_at)
      timestamps(type: :utc_datetime_usec)
    end
  end
end
