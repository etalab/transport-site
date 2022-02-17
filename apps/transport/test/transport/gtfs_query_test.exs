defmodule Transport.GtfsQueryTest do
  use ExUnit.Case
  import DB.Factory
  import Transport.Jobs.GtfsToDB

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  defp insert_a_departure(opts) do
    data_import_id = Keyword.fetch!(opts, :data_import_id)
    departure_time = Keyword.fetch!(opts, :departure_time)
    trip_id = Keyword.get(opts, :trip_id, "trip_1")
    stop_id = Keyword.get(opts, :stop_id, "stop_1")
    service_id = Keyword.get(opts, :service_id, "service_1")
    route_id = Keyword.get(opts, :route_id, "route_1")
    days = Keyword.get(opts, :days, [1, 2, 3, 4, 5, 6, 7])

    :gtfs_stop_times
    |> insert(
      data_import_id: data_import_id,
      trip_id: trip_id,
      departure_time: departure_time,
      stop_id: stop_id
    )

    :gtfs_trips
    |> insert(
      data_import_id: data_import_id,
      service_id: service_id,
      trip_id: trip_id,
      route_id: route_id
    )

    :gtfs_calendar
    |> insert(
      data_import_id: data_import_id,
      service_id: service_id,
      start_date: Date.new!(2022, 1, 1),
      end_date: Date.new!(2022, 1, 31),
      days: days
    )

    %{
      data_import_id: data_import_id,
      departure_time: departure_time,
      trip_id: trip_id,
      stop_id: stop_id,
      service_id: service_id,
      route_id: route_id,
      days: days
    }
  end

  describe "compute next departures" do
    test "very simple case" do
      departure_time = "08:05:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      %{
        trip_id: trip_id,
        stop_id: stop_id,
        service_id: service_id,
        route_id: route_id
      } = insert_a_departure(data_import_id: data_import_id, departure_time: departure_time)

      # find one departure in the next 10 minutes after 8am
      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-01 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-01 08:05:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = next_departure

      # find no departure after 8:10am
      assert [] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-01 08:10:00Z], 10)
    end

    test "handle calendar_dates exception (remove date)" do
      departure_time = "08:05:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      %{service_id: service_id, stop_id: stop_id} =
        insert_a_departure(data_import_id: data_import_id, departure_time: departure_time)

      # add exception for 2022-01-15
      :gtfs_calendar_dates
      |> insert(
        data_import_id: data_import_id,
        service_id: service_id,
        date: Date.new!(2022, 1, 15),
        # exception_type 2 means "remove"
        exception_type: 2
      )

      # find one departure the 14th and the 16th
      assert [_next_departure] =
               Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-14 08:00:00Z], 10)

      assert [_next_departure] =
               Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-16 08:00:00Z], 10)

      # find no departure the 15th
      assert [] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-15 08:00:00Z], 10)
    end

    test "handle calendar_dates exception (add date)" do
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

      # add exception for 2022-01-15
      :gtfs_calendar_dates
      |> insert(
        data_import_id: data_import_id,
        service_id: service_id,
        date: Date.new!(2022, 1, 15),
        # exception_type 1 means "add"
        exception_type: 1
      )

      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-15 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-15 08:05:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = next_departure
    end

    test "handle calendar_dates exception (add date) when there is an associated calendar" do
      departure_time = "08:05:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      # sundays only
      %{service_id: service_id, stop_id: stop_id, route_id: route_id, trip_id: trip_id} =
        insert_a_departure(data_import_id: data_import_id, departure_time: departure_time, days: [7])

      # add exception for 2022-01-15 (a saturday)
      :gtfs_calendar_dates
      |> insert(
        data_import_id: data_import_id,
        service_id: service_id,
        date: Date.new!(2022, 1, 15),
        # exception_type 1 means "add"
        exception_type: 1
      )

      # the added exception day
      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-15 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-15 08:05:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = next_departure

      # the regular schedule (a sunday)
      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-16 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-16 08:05:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = next_departure

      # nothing the next day (a monday)
      assert [] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-17 08:00:00Z], 10)
    end

    test "filter departures on data_import_id" do
      departure_time_1 = "08:05:00" |> cast_binary_to_interval()
      departure_time_2 = "08:06:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id_1} = :data_import |> insert(resource_history_id: resource_history_id)
      %{id: data_import_id_2} = :data_import |> insert(resource_history_id: resource_history_id)

      %{service_id: service_id, stop_id: stop_id, route_id: route_id, trip_id: trip_id} =
        insert_a_departure(data_import_id: data_import_id_1, departure_time: departure_time_1)

      insert_a_departure(data_import_id: data_import_id_2, departure_time: departure_time_2)

      # data_import_1
      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id_1, ~U[2022-01-15 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-15 08:05:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = next_departure

      # data_import_2
      [next_departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id_2, ~U[2022-01-15 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-15 08:06:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = next_departure
    end

    test "two departures from different trips on the same stop" do
      departure_time_1 = "08:05:00" |> cast_binary_to_interval()
      departure_time_2 = "08:06:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      %{service_id: service_id, stop_id: stop_id, route_id: route_id, trip_id: trip_id} =
        insert_a_departure(data_import_id: data_import_id, departure_time: departure_time_1)

      %{service_id: service_id_2, route_id: route_id_2, trip_id: trip_id_2} =
        insert_a_departure(
          data_import_id: data_import_id,
          departure_time: departure_time_2,
          trip_id: "other_trip",
          route_id: "other_route",
          service_id: "service_2"
        )

      [departure1, departure2] =
        Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-15 08:00:00Z], 10)

      assert %{
               "departure" => ~N[2022-01-15 08:05:00.000000],
               "route_id" => ^route_id,
               "service_id" => ^service_id,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id
             } = departure1

      assert %{
               "departure" => ~N[2022-01-15 08:06:00.000000],
               "route_id" => ^route_id_2,
               "service_id" => ^service_id_2,
               "stop_id" => ^stop_id,
               "trip_id" => ^trip_id_2
             } = departure2
    end

    test "a departure with a departure_time > 24:00" do
      departure_time = "26:05:00" |> cast_binary_to_interval()

      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      %{stop_id: stop_id} =
        insert_a_departure(data_import_id: data_import_id, departure_time: departure_time, days: [7])

      # service_id is active on sundays (2022-01-16 for example)
      # as the departure_time is > 24:00, the actual departure is the next day (2022-01-17 for example)
      [departure] = Transport.GtfsQuery.next_departures(stop_id, data_import_id, ~U[2022-01-17 02:00:00Z], 10)

      # actual time is 26:05 - 24:00 => 02:05
      assert %{"departure" => ~N[2022-01-17 02:05:00.000000]} = departure
    end
  end
end
