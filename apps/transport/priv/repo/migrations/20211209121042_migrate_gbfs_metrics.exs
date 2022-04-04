defmodule DB.Repo.Migrations.MigrateGBFSMetrics do
  use Ecto.Migration
  alias Ecto.Adapters.SQL

  def up do
    # For existing GBFS metrics:
    # - Rename internal to external
    # - Rename external to internal
    # - Sum internal + external -> external for same target and period
    """
    update metrics set event = 'gbfs:request:old_internal' where event = 'gbfs:request:internal';
    update metrics set event = 'gbfs:request:internal' where event = 'gbfs:request:external';
    update metrics set event = 'gbfs:request:external' where event = 'gbfs:request:old_internal';

    update metrics set count = t.sum
    from (
        select period, target, sum(count) sum
        from metrics
        where event in ('gbfs:request:external', 'gbfs:request:internal')
        group by 1, 2
    ) t
    where t.period = metrics.period and t.target = metrics.target and metrics.event = 'gbfs:request:external';
    """
    |> String.split(";")
    |> Enum.each(fn q -> DB.Repo |> SQL.query!(q) end)
  end

  def down do
    IO.puts("No going back")
  end
end
