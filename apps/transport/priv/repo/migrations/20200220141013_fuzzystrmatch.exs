defmodule DB.Repo.Migrations.Fuzzystrmatch do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS fuzzystrmatch", "DROP EXTENSION fuzzystrmatch")
  end
end
