# mix run scripts/irve/dump-simple-consolidation.exs
# script to dump `DB.IRVEValidPDC` table into a local CSV
# (then you can use `stats.exs` to include it into the comparison with previous consolidations)

target = Path.join(__DIR__, "../../cache-dir/simple-consolidation.csv")

IO.puts("Saving to #{target}")
Transport.IRVE.DatabaseExporter.export_to_csv(target)
