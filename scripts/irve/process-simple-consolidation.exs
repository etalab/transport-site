# mix run scripts/irve/process-simple-consolidation.exs
# For local dev use, with more debug options and without setting up MinIO:
# DEBUG=1 DESTINATION=local_disk mix run scripts/irve/process-simple-consolidation.exs

import Ecto.Query
Logger.configure(level: :info)

IO.puts("Number of valid PDCs in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")

IO.puts(
  "Number of distinct id_pdc_itinerance in these PDCs: #{DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))}"
)

IO.puts("Number of valid files in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")

destination = if System.get_env("DESTINATION") == "local_disk", do: :local_disk, else: :send_to_s3

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

report_df = Transport.IRVE.SimpleConsolidation.process(destination: destination)

# Nicely displays what happened
if System.get_env("DEBUG") == "1" do
  report_df["status"]
  |> Explorer.Series.frequencies()
  |> IO.inspect(IEx.inspect_opts())
end

IO.puts("Number of valid PDCs now in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")

IO.puts(
  "Number of distinct id_pdc_itinerance in these PDCs: #{DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))}"
)

IO.puts("Number of valid files now in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")
