defmodule DB.Repo.Migrations.CreateResourceHistoryFormatIndex do
  use Ecto.Migration

  @index_name "resource_history_payload_format"

  def up do
    execute("CREATE INDEX #{@index_name} ON resource_history((payload->>'format'));")
  end

  def down do
    execute("DROP INDEX #{@index_name};")
  end
end
