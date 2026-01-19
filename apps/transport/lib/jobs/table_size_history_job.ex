defmodule Transport.Jobs.TableSizeHistoryJob do
  @moduledoc """
  Write, for each table, the space taken in the database.
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    query = """
    WITH RECURSIVE pg_inherit(inhrelid, inhparent) AS
     (select inhrelid, inhparent
     FROM pg_inherits
     UNION
     SELECT child.inhrelid, parent.inhparent
     FROM pg_inherit child, pg_inherits parent
     WHERE child.inhparent = parent.inhrelid),
    pg_inherit_short AS (SELECT * FROM pg_inherit WHERE inhparent NOT IN (SELECT inhrelid FROM pg_inherit))
    SELECT
    	table_name,
    	total_bytes::bigint AS size,
    	current_date as date
    FROM (
     SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
     FROM (
          SELECT c.oid
               , nspname AS table_schema
               , relname AS TABLE_NAME
               , SUM(c.reltuples) OVER (partition BY parent) AS row_estimate
               , SUM(pg_total_relation_size(c.oid)) OVER (partition BY parent) AS total_bytes
               , SUM(pg_indexes_size(c.oid)) OVER (partition BY parent) AS index_bytes
               , SUM(pg_total_relation_size(reltoastrelid)) OVER (partition BY parent) AS toast_bytes
               , parent
           FROM (
                 SELECT pg_class.oid
                     , reltuples
                     , relname
                     , relnamespace
                     , pg_class.reltoastrelid
                     , COALESCE(inhparent, pg_class.oid) parent
                 FROM pg_class
                     LEFT JOIN pg_inherit_short ON inhrelid = oid
                 WHERE relkind IN ('r', 'p')
              ) c
              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
              WHERE nspname = 'public' AND relname not in (select hypertable_name FROM timescaledb_information.hypertables)
    ) a
    WHERE oid = parent
    ) a

    UNION

    SELECT
        hypertable_name as table_name,
        hypertable_size(format('%I.%I', hypertable_schema, hypertable_name)) as size,
        current_date as date
    FROM timescaledb_information.hypertables
    """

    %{columns: columns, rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, query)

    columns = Enum.map(columns, &String.to_existing_atom/1)
    rows = Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)

    DB.Repo.insert_all(DB.TableSizeHistory, rows)

    :ok
  end
end
