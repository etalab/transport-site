defmodule DB.Repo.Migrations.DatasetRemoveParis2024Tag do
  use Ecto.Migration

  def up do
    execute("UPDATE dataset SET custom_tags = array_remove(custom_tags, 'paris2024')")
  end

  def down do
    IO.puts("No going back")
  end
end
