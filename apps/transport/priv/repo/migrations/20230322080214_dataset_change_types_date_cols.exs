defmodule DB.Repo.Migrations.DatasetChangeTypesDateCols do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE dataset ALTER COLUMN created_at TYPE timestamp without time zone USING created_at::timestamp;")

    execute(
      "ALTER TABLE dataset ALTER COLUMN last_update TYPE timestamp without time zone USING last_update::timestamp;"
    )

    execute("ALTER TABLE dataset ALTER COLUMN created_at SET NOT NULL;")
    execute("ALTER TABLE dataset ALTER COLUMN last_update SET NOT NULL;")
  end

  def down do
    execute("ALTER TABLE dataset ALTER COLUMN created_at TYPE varchar USING created_at::date;")
    execute("ALTER TABLE dataset ALTER COLUMN last_update TYPE varchar USING last_update::date;")
    execute("ALTER TABLE dataset ALTER COLUMN created_at DROP NOT NULL;")
    execute("ALTER TABLE dataset ALTER COLUMN last_update DROP NOT NULL;")
  end
end
