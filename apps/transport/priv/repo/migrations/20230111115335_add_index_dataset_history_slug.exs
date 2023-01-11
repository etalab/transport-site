defmodule DB.Repo.Migrations.AddIndexDatasetHistorySlug do
  use Ecto.Migration

  @index_name "dataset_history_payload_slug"

  def up do
    # ->> operator returns text, index it as an integer
    # as slug is an integer and will be compared against
    # integers
    execute("CREATE INDEX #{@index_name} ON dataset_history((payload->>'slug'));")
  end

  def down do
    execute("DROP INDEX #{@index_name};")
  end
end
