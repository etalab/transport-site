defmodule Transport.GtfsQuery do
  @moduledoc """
  Make queries on gtfs data imports for useful information extraction.
  e.g. Get next departures from a stop
  """

  def next_departures(stop_id, import_id, datetime_start, window_in_minutes) do
    datetime_end = DateTime.add(datetime_start, window_in_minutes * 60, :second)
    no_dates_before = datetime_start |> DateTime.to_date() |> Date.add(-2)

    query = """
      with stop_times as (select gst.*, gt.route_id, gt.service_id, gc.days, gc.start_date, gc.end_date from gtfs_stop_times gst
      left join gtfs_trips gt on gst.trip_id = gt.trip_id and gst.data_import_id = gt.data_import_id
      left join gtfs_calendar gc on gc.service_id = gt.service_id and gst.data_import_id = gc.data_import_id
      where stop_id = $1 and gst.data_import_id = $2),
      service_ids as (select distinct(service_id) from stop_times),
      days_list as (
        with gs as (
        select generate_series(start_date, end_date, '1 day') as day, days, service_id from gtfs_calendar where service_id in (select * from service_ids) and end_date > $5 and data_import_id = $2
        ),
        gdow as (
        select day::date, days, extract (isodow from day) as dow, service_id from gs
        ),
        exception_add as (
        select date as day, service_id from gtfs_calendar_dates where exception_type = 1 and service_id in (select * from service_ids) and data_import_id = $2
        ),
        exception_remove as (
        select date as day, service_id from gtfs_calendar_dates where exception_type = 2 and service_id in (select * from service_ids) and data_import_id = $2
        ),
        res as (
        select * from gdow where dow = any(days) and day not in (select day from exception_remove er where er.service_id = gdow.service_id)
        union select day, '{}', extract (isodow from day), service_id from exception_add
        )
        select distinct on (day, service_id) day, service_id from res order by day asc
      ),
      departures as (
      select st.*, dl.day, dl.day + '12:00:00'::time - interval '12 hours' + st.departure_time as real_departure from stop_times st left join days_list dl on dl.service_id = st.service_id
      )
      select stop_id, trip_id, route_id, service_id, real_departure as departure from departures where real_departure > $3 and real_departure < $4 order by real_departure asc;
    """

    %{columns: columns, rows: rows} =
      Ecto.Adapters.SQL.query!(DB.Repo, query, [stop_id, import_id, datetime_start, datetime_end, no_dates_before])

    rows |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
  end
end
