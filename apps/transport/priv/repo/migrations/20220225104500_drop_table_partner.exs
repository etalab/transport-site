defmodule DB.Repo.Migrations.DropTablePartner do
  use Ecto.Migration

  def up do
    drop_if_exists table("partner")
  end

  def down do
    IO.puts("no going back")
  end
end
