defmodule DB.Repo.Migrations.AddTimestampsDataImport do
  use Ecto.Migration

  def change do
    alter table(:data_import) do
      timestamps([type: :utc_datetime_usec])
    end
  end
end
