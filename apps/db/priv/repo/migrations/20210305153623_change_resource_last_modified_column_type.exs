defmodule DB.Repo.Migrations.ChangeResourceLastModifiedColumnType do
  use Ecto.Migration

  def change do
    execute(string_to_date("resource"), date_to_string("resource"))
    execute(string_to_date("dataset"), date_to_string("dataset"))
  end

  defp string_to_date(table) do
    "alter table #{table} alter last_update type timestamptz using last_update::timestamptz"
  end

  defp date_to_string(table) do
    "alter table #{table} alter last_update type varchar(255) using last_update::varchar(255)"
  end
end
