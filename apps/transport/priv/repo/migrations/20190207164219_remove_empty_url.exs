defmodule Transport.Repo.Migrations.RemoveEmptyUrl do
  use Ecto.Migration

  def change do
    execute "DELETE FROM resource WHERE url IS NULL"

  end
end
