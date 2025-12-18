defmodule DB.Repo.Migrations.AutocompleteAddDataset do
  use Ecto.Migration

  def up do
    (Application.app_dir(:transport, "priv") <> "/repo/migrations/sql/autocomplete_add_dataset.sql")
    |> File.read!()
    |> String.split("|")
    |> Enum.each(fn q -> DB.Repo |> Ecto.Adapters.SQL.query!(q) end)
  end

  def down, do: IO.puts("No going back")
end
