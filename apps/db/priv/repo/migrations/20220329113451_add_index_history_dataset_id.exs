defmodule DB.Repo.Migrations.AddIndexHistoryDatasetId do
  use Ecto.Migration

  @index_name "resource_history_payload_dataset_id"

  def up do
    # ->> operator returns text, index it as an integer
    # as dataset_id is an integer and will be compared against
    # integers
    execute("CREATE INDEX #{@index_name} ON resource_history(cast(payload->>'dataset_id' as bigint));")
  end

  def down do
    execute("DROP INDEX #{@index_name};")
  end
end
