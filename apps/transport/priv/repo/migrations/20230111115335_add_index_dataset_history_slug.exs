defmodule DB.Repo.Migrations.AddIndexDatasetHistorySlug do
  use Ecto.Migration

  @index_name "dataset_history_payload_slug"

  def up do
    execute("CREATE INDEX #{@index_name} ON dataset_history((payload->>'slug'));")
  end

  def down do
    execute("DROP INDEX #{@index_name};")
  end
end
