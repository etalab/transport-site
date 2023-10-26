defmodule DB.Repo.Migrations.ResourceChangeTypesDateTimeCols do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE resource ALTER COLUMN last_import TYPE timestamp without time zone USING last_import::timestamp;"
    )

    execute(
      "ALTER TABLE resource ALTER COLUMN last_update TYPE timestamp without time zone USING last_update::timestamp;"
    )

    execute("ALTER TABLE resource ALTER COLUMN last_import SET NOT NULL;")
    execute("ALTER TABLE resource ALTER COLUMN last_update SET NOT NULL;")
  end

  def down do
    execute("ALTER TABLE resource ALTER COLUMN last_import TYPE varchar USING last_import::varchar;")
    execute("ALTER TABLE resource ALTER COLUMN last_update TYPE varchar USING last_update::varchar;")
    execute("ALTER TABLE resource ALTER COLUMN last_import DROP NOT NULL;")
    execute("ALTER TABLE resource ALTER COLUMN last_update DROP NOT NULL;")
  end
end
