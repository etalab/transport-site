import Ecto.Query

require Logger

# TODO: use a scalable pattern (e.g. chunked by data import would work), since it will time out here.
# Keeping for reference during development.

Logger.info("Loading data import ids...")

data_import_ids =
  DB.DataImport
  |> select([di], di.id)
  |> DB.Repo.all()
  |> IO.inspect(IEx.inspect_opts())

Logger.info("Loading stops...")

# TODO: reduce query time (test: index on data_import_id reduces time by 2)
# TODO: avoid data marshalling (650k records), use simplest structure (arrays, not maps)
DB.GTFS.Stops
|> where([s], s.data_import_id in ^data_import_ids)
|> select([s], [s.stop_lat, s.stop_lon])
|> DB.Repo.all()
|> Enum.take(1)
|> IO.inspect()
