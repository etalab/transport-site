# mix run scripts/irve/process-simple-consolidation.exs
# Options:
# --destination : either "local_disk" or "send_to_s3" (default: "send_to_s3")
# --debug : if present, will print a summary of the report at the end and log each processed item
# Advised dev use: mix run scripts/irve/process-simple-consolidation.exs --destination local_disk --debug

import Ecto.Query
Logger.configure(level: :info)

{opts, _args, _} =
  OptionParser.parse(System.argv(),
    switches: [destination: :string, debug: :boolean]
  )

destination =
  case opts[:destination] do
    "local_disk" -> :local_disk
    _ -> :send_to_s3
  end

debug = opts[:debug]

IO.puts("Number of valid PDCs in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")

IO.puts(
  "Number of distinct id_pdc_itinerance in these PDCs: #{DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))}"
)

IO.puts("Number of valid files in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")

IO.puts("Using destination: #{destination}")

# delete everything
DB.Repo.delete_all(DB.IRVEValidFile)

# Delete a bit so that we can demonstrate "already imported"
# IO.puts("deleting a bit of imported files")
# import Ecto.Query
# DB.Repo.delete_all(
#  from(f in DB.IRVEValidFile,
#    where: f.id in subquery(from(f2 in DB.IRVEValidFile, select: f2.id, limit: 100))
#  )
# )

report_df = Transport.IRVE.SimpleConsolidation.process(destination: destination, debug: debug)

# Nicely displays what happened
if debug do
  report_df["status"]
  |> Explorer.Series.frequencies()
  |> IO.inspect(IEx.inspect_opts())
end

IO.puts("Number of valid PDCs now in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")

IO.puts(
  "Number of distinct id_pdc_itinerance in these PDCs: #{DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))}"
)

IO.puts("Number of valid files now in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")
