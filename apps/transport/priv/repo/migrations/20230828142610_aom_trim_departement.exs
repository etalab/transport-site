defmodule DB.Repo.Migrations.AomTrimDepartement do
  use Ecto.Migration

  def up do
    execute("update aom set departement = trim(departement)")
  end

  def down do
    IO.puts("No going back")
  end
end
