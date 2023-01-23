defmodule Transport.GTFSExportStops do
  import Ecto.Query

  def data_import_ids do
    DB.DataImport
    |> select([di], di.id)
    |> DB.Repo.all()
  end

  def build_stops_report(data_import_ids) do
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
  end

  @headers [
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

  @doc """
  A flat export for the bizdev team to have a closer look at data.
  """
  def export_stops_report(data_import_ids) do
    headers = @headers |> Enum.map(fn x -> Atom.to_string(x) end)

    rows =
      build_stops_report(data_import_ids)
      |> DB.Repo.all()
      |> Enum.map(fn record ->
        # build a list with same order as the headers
        for header <- @headers, do: Map.fetch!(record, header)
      end)

    ([headers] ++ rows)
    |> NimbleCSV.RFC4180.dump_to_iodata()
  end
end
