import Ecto.Query

require Logger

# TODO: use a scalable pattern (e.g. chunked by data import would work), since it will time out here.
# Keeping for reference during development.
Logger.info("Loading data import ids...")

data_import_ids =
  DB.DataImport
  |> select([di], di.id)
  |> DB.Repo.all()
  #  |> Enum.take(1)
  |> IO.inspect(IEx.inspect_opts())

Logger.info("Loading stops...")

# TODO: reduce query time (test: index on data_import_id reduces time by 2)
DB.GTFS.Stops
|> where([s], s.data_import_id in ^data_import_ids)
|> join(:inner, [s], di in DB.DataImport, on: s.data_import_id == di.id)
|> join(:inner, [_, di], rh in DB.ResourceHistory, on: di.resource_history_id == rh.id)
|> join(:inner, [_, _, rh], r in DB.Resource, on: rh.resource_id == r.id)
|> join(:inner, [_, _, _, r], d in DB.Dataset, on: r.dataset_id == d.id)
|> select([s, di, rh, r, d], %{
  dataset_custom_title: d.custom_title,
  dataset_organisation: d.organization,
  dataset_id: d.id,
  resource_id: r.id,
  dataset_aom_id: d.aom_id,
  dataset_region_id: d.region_id,
  stop_id: s.stop_id,
  stop_name: s.stop_name,
  stop_lat: s.stop_lat,
  stop_lon: s.stop_lon,
  stop_location_type: s.location_type
})
|> DB.Repo.all()
|> CSV.encode(
  headers: [
    :dataset_custom_title,
    :dataset_organisation,
    :dataset_id,
    :resource_id,
    :dataset_aom_id,
    :dataset_region_id,
    :stop_id,
    :stop_name,
    :stop_lat,
    :stop_lon,
    :stop_location_type
  ]
)
|> Enum.to_list()
|> Enum.join()
|> IO.puts()
