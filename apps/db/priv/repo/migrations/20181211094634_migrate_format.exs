defmodule DB.Repo.Migrations.MigrateFormat do
  use Ecto.Migration
  alias Ecto.Adapters.SQL
  alias DB.Repo

  def change do
    alter table(:resource) do
      add :format, :string
      add :last_import, :string
    end

    flush()

    {:ok, _} = SQL.query(Repo, """
    UPDATE resource
    SET format = dataset.format, last_import = dataset.last_import
    FROM dataset
    WHERE dataset_id = dataset.id
    """)

    alter table(:dataset) do
      remove :format
      remove :last_import
      remove :coordinates
      remove :task_id
    end
  end
end
