defmodule DB.Repo.Migrations.PlacesRenameAutocomplete do
  use Ecto.Migration

  def up do
    (Application.app_dir(:transport, "priv") <> "/repo/migrations/sql/places_rename_autocomplete.sql")
    |> File.read!()
    |> String.split("|")
    |> Enum.each(fn q -> DB.Repo |> Ecto.Adapters.SQL.query!(q) end)
  end

  def down, do: IO.puts("No going back")
end
