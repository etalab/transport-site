# mix run --no-start scripts/irve/dump-consolidation.exs [path]
#
# Exports the IRVE PDCs currently in DB (`DB.IRVEValidPDC`, duplicates included) to a CSV without running the
# consolidation, e.g. after restoring a production backup. Default path: cache-dir/irve/db-<date>.csv.
# Then compare it: mix run --no-start scripts/irve/compare.exs cache-dir/irve/db-<date>.csv datagouv

Logger.configure(level: :info)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = DB.Repo.start_link()
{:ok, _} = Transport.CachedFiles.start_link([])

target = List.first(System.argv()) || Path.expand("../../cache-dir/irve/db-#{Date.utc_today()}.csv", __DIR__)
File.mkdir_p!(Path.dirname(target))

IO.puts("Saving to #{Path.relative_to_cwd(target)}")
Transport.IRVE.DatabaseExporter.export_to_csv(target)
