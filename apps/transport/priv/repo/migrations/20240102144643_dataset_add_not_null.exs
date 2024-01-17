defmodule DB.Repo.Migrations.DatasetAddNotNull do
  use Ecto.Migration

  @attributes [
    :datagouv_id,
    :custom_title,
    :licence,
    :logo,
    :full_logo,
    :slug,
    :tags,
    :datagouv_title,
    :type,
    :frequency,
    :has_realtime,
    :is_active,
    :nb_reuses
  ]

  def up do
    Enum.each(@attributes, fn attribute ->
      execute("ALTER TABLE dataset ALTER COLUMN #{attribute} SET NOT NULL")
    end)
  end

  def down do
    Enum.each(@attributes, fn attribute ->
      execute("ALTER TABLE dataset ALTER COLUMN #{attribute} DROP NOT NULL")
    end)
  end
end
