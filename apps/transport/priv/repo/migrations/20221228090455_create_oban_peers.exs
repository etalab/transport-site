defmodule DB.Repo.Migrations.CreateObanPeers do
  # https://hexdocs.pm/oban/2.12.1/v2-11.html
  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 11)

  def down, do: Oban.Migrations.down(version: 11)
end
