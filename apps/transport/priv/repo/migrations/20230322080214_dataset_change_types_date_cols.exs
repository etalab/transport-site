defmodule DB.Repo.Migrations.DatasetChangeTypesDateCols do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE dataset ALTER COLUMN created_at TYPE timestamp without time zone SET NOT NULL USING created_at::timestamp;"
    execute "ALTER TABLE dataset ALTER COLUMN last_update TYPE timestamp without time zone SET NOT NULL USING last_update::timestamp;"
  end

  def down do
    execute "ALTER TABLE dataset ALTER COLUMN created_at TYPE varchar;"
    execute "ALTER TABLE dataset ALTER COLUMN last_update TYPE varchar;"
  end
end
