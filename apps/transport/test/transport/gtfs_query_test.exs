defmodule Transport.GtfsQueryTest do
  use ExUnit.Case
  import DB.Factory
  import Transport.Jobs.GtfsToDB

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "compute next departures" do
    test "very simple case" do
      departure_time = "08:05:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      :gtfs_stop_times
      |> insert(
        data_import_id: data_import_id,
        trip_id: trip_id = "trip_1",
        departure_time: departure_time,
        stop_id: stop_id = "stop_1"
      )

      :gtfs_trips
      |> insert(
        data_import_id: data_import_id,
        service_id: service_id = "service_1",
        trip_id: trip_id,
        route_id: route_id = "route_1"
      )

      :gtfs_calendar
      |> insert(
        data_import_id: data_import_id,
        service_id: service_id,
        start_date: Date.new!(2022, 1, 1),
        end_date: Date.new!(2022, 1, 31),
        days: [1, 2, 3, 4, 5, 6, 7]
      )

      # find one departure in the next 10 minutes after 8am
      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-01 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-01 08:05:00.000000],
               "route_id" => route_id,
               "service_id" => service_id,
               "stop_id" => stop_id,
               "trip_id" => trip_id
             } = next_departure

      # find no departure after 8:10am
      assert [] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-01 08:10:00Z], 10)
    end
  end
end
