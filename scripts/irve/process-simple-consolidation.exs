# mix run scripts/irve/process-simple-consolidation.exs

Logger.configure(level: :info)

import Ecto.Query

IO.puts("deleting a bit of imported files")
# delete but not everything, so that we can demonstrate "already imported"
DB.Repo.delete_all(
  from(f in DB.IRVEValidFile,
    where: f.id in subquery(from(f2 in DB.IRVEValidFile, select: f2.id, limit: 100))
  )
)

Transport.IRVE.SimpleConsolidation.process(destination: :local_disk)
