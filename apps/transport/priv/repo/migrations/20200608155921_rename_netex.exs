defmodule DB.Repo.Migrations.RenameNetex do
  use Ecto.Migration

  def change do
    execute "UPDATE resource SET format = 'NeTEx' where format = 'netex';"
  end
end
