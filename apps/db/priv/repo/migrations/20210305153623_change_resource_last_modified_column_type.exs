defmodule DB.Repo.Migrations.ChangeResourceLastModifiedColumnType do
  use Ecto.Migration

  def change do
    execute(string_to_date(), date_to_string())
  end

  defp string_to_date() do
    "alter table resource alter last_update type timestamptz using last_update::timestamptz"
  end

  defp date_to_string() do
    "alter table resource alter last_update type varchar(255) using last_update::varchar(255)"
  end
end
