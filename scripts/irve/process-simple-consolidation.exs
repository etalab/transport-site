# mix run scripts/irve/process-simple-consolidation.exs
# Or with more debug info: DEBUG=1 mix run scripts/irve/process-simple-consolidation.exs

Logger.configure(level: :info)

# import Ecto.Query

# delete everything
DB.Repo.delete_all(DB.IRVEValidFile)

# Delete a bit so that we can demonstrate "already imported"
# IO.puts("deleting a bit of imported files")

# DB.Repo.delete_all(
#  from(f in DB.IRVEValidFile,
#    where: f.id in subquery(from(f2 in DB.IRVEValidFile, select: f2.id, limit: 100))
#  )
# )

Transport.IRVE.SimpleConsolidation.process(destination: :local_disk)

IO.puts("Number of valid PDCs now in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")
IO.puts("Number of valid files now in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")
