defmodule Transport.GTFSExportStops do
  @moduledoc """
  A module to generate a flat-report from GTFS stops into a CSV for biz-devs.
  """
  import Ecto.Query

  def data_import_ids do
    DB.DataImport
    |> select([di], di.id)
    |> order_by([di], di.id)
    |> DB.Repo.all()
  end

  def build_stops_report(data_import_ids) do
    DB.GTFS.Stops
    |> where([s], s.data_import_id in ^data_import_ids)
    |> order_by([s], [s.data_import_id, s.id])
    |> join(:inner, [s], di in DB.DataImport, on: s.data_import_id == di.id)
    |> join(:inner, [_, di], rh in DB.ResourceHistory, on: di.resource_history_id == rh.id)
    |> join(:inner, [_, _, rh], r in DB.Resource, on: rh.resource_id == r.id)
    |> join(:inner, [_, _, _, r], d in DB.Dataset, on: r.dataset_id == d.id)
    |> select([s, di, rh, r, d], %{
      dataset_custom_title: d.custom_title,
      dataset_organisation: d.organization,
      dataset_id: d.id,
      dataset_datagouv_id: d.datagouv_id,
      resource_id: r.id,
      resource_datagouv_id: r.datagouv_id,
      resource_title: r.title,
      dataset_aom_id: d.aom_id,
      dataset_region_id: d.region_id,
      di_id: di.id,
      stop_id: s.stop_id,
      stop_name: s.stop_name,
      stop_lat: s.stop_lat,
      stop_lon: s.stop_lon,
      location_type: s.location_type
    })
  end

  @headers [
    :dataset_custom_title,
    :dataset_organisation,
    :dataset_id,
    :dataset_datagouv_id,
    :resource_id,
    :resource_datagouv_id,
    :resource_title,
    :dataset_aom_id,
    :dataset_region_id,
    :di_id,
    :stop_id,
    :stop_name,
    :stop_lat,
    :stop_lon,
    :location_type
  ]

  def export_headers do
    @headers
    |> Enum.map(fn x -> Atom.to_string(x) end)
  end

  @doc """
  A flat export for the bizdev team to have a closer look at data.
  """
  def export_stops_report(data_import_ids) do
    data_import_ids
    |> build_stops_report()
    |> DB.Repo.all()
    |> Enum.map(fn record ->
      # build a list with same order as the headers
      for header <- @headers, do: Map.fetch!(record, header)
    end)
  end
end
