defmodule DB.Repo.Migrations.Unaccent do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS unaccent")
  end
end
