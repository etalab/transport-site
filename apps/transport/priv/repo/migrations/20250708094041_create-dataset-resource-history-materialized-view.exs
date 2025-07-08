defmodule :"Elixir.DB.Repo.Migrations.Create-dataset-resource-history-materialized-view" do
  use Ecto.Migration

  def up do
    execute("""
    CREATE MATERIALIZED VIEW resource_history_mv AS
    SELECT
      rh.*,
      (rh.payload->>'dataset_id')::bigint AS dataset_id,
      mv_latest.id AS latest_multivalidation_id
    FROM
      resource_history rh
    LEFT JOIN LATERAL (
      SELECT mv.id
      FROM multi_validation mv
      WHERE mv.resource_history_id = rh.id
      ORDER BY mv.inserted_at DESC
      LIMIT 1
    ) mv_latest ON TRUE;
    """)

    execute("CREATE INDEX ON resource_history_mv (dataset_id);")
    execute("CREATE INDEX ON resource_history_mv (latest_multivalidation_id);")
    execute("CREATE INDEX ON resource_history_mv (resource_id);")
  end

  def down do
    execute("DROP INDEX IF EXISTS resource_history_mv_dataset_id_idx;")
    execute("DROP INDEX IF EXISTS resource_history_mv_latest_multivalidation_id_idx;")
    execute("DROP INDEX IF EXISTS resource_history_mv_resource_id_idx;")

    execute("DROP MATERIALIZED VIEW IF EXISTS resource_history_mv;")
  end
end
