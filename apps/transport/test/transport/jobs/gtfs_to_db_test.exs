defmodule Transport.Jobs.GtfsToDBTest do
  use ExUnit.Case
  import DB.Factory
  import Transport.Jobs.GtfsToDB
  doctest Transport.Jobs.GtfsToDB, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "import a GTFS file to the database" do
    test "import stop_times" do
      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      file_stream = stream_local_file("stop_times.txt", "#{__DIR__}/../../fixture/files/gtfs_import.zip")
      stop_times_stream_insert(file_stream, data_import_id)

      assert [stop_time_1, stop_time_2] = DB.GTFS.StopTimes |> DB.Repo.all()

      arrival_time = struct(Postgrex.Interval, cast_binary_to_interval("08:05:00"))
      departure_time = struct(Postgrex.Interval, cast_binary_to_interval("08:06:00"))

      assert %{
               stop_id: "stop_1",
               data_import_id: ^data_import_id,
               stop_sequence: 1,
               trip_id: "trip_1",
               arrival_time: ^arrival_time,
               departure_time: ^departure_time
             } = stop_time_1

      time = struct(Postgrex.Interval, cast_binary_to_interval("08:10:00"))

      assert %{
               stop_id: "stop_2",
               data_import_id: ^data_import_id,
               stop_sequence: 1,
               trip_id: "trip_2",
               arrival_time: ^time,
               departure_time: ^time
             } = stop_time_2
    end

    test "import stops" do
      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      file_stream = stream_local_file("stops.txt", "#{__DIR__}/../../fixture/files/gtfs_import.zip")
      stops_stream_insert(file_stream, data_import_id)

      assert [stop_1, stop_2] = DB.GTFS.Stops |> DB.Repo.all()

      assert %{
               stop_id: "stop_1",
               data_import_id: ^data_import_id,
               stop_name: "Frioul",
               stop_lat: 43.28,
               stop_lon: 5.3,
               location_type: 1
             } = stop_1

      assert %{
               stop_id: "stop_2",
               data_import_id: ^data_import_id,
               stop_name: "stop_name",
               location_type: 2
             } = stop_2
    end

    test "import calendar" do
      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      file_stream = stream_local_file("calendar.txt", "#{__DIR__}/../../fixture/files/gtfs_import.zip")
      calendar_stream_insert(file_stream, data_import_id)

      assert [cal_1, cal_2] = DB.GTFS.Calendar |> DB.Repo.all()

      assert %{
               service_id: "service_1",
               data_import_id: ^data_import_id,
               days: [1, 2, 3, 4, 5, 6, 7],
               start_date: ~D[2022-01-01],
               end_date: ~D[2022-01-31]
             } = cal_1

      assert %{
               service_id: "service_2",
               data_import_id: ^data_import_id,
               days: [1, 3, 7],
               start_date: ~D[2022-06-01],
               end_date: ~D[2023-01-31]
             } = cal_2
    end

    test "import calendar dates" do
      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      file_stream = stream_local_file("calendar_dates.txt", "#{__DIR__}/../../fixture/files/gtfs_import.zip")
      calendar_dates_stream_insert(file_stream, data_import_id)

      assert [cald_1, cald_2] = DB.GTFS.CalendarDates |> DB.Repo.all()

      assert %{
               service_id: "service_1",
               data_import_id: ^data_import_id,
               date: ~D[2022-01-15],
               exception_type: 1
             } = cald_1

      assert %{
               service_id: "service_2",
               data_import_id: ^data_import_id,
               date: ~D[2022-01-16],
               exception_type: 2
             } = cald_2
    end

    test "import trips" do
      %{id: resource_history_id} = :resource_history |> insert(payload: %{})
      %{id: data_import_id} = :data_import |> insert(resource_history_id: resource_history_id)

      file_stream = stream_local_file("trips.txt", "#{__DIR__}/../../fixture/files/gtfs_import.zip")
      trips_stream_insert(file_stream, data_import_id)

      assert [trip_1, trip_2] = DB.GTFS.Trips |> DB.Repo.all()

      assert %{
               route_id: "route_1",
               service_id: "service_1",
               trip_id: "trip_1",
               data_import_id: ^data_import_id
             } = trip_1

      assert %{
               route_id: "route_2",
               service_id: "service_2",
               trip_id: "trip_2",
               data_import_id: ^data_import_id
             } = trip_2
    end
  end

  def stream_local_file(file_name, zip_path) do
    zip_file = Unzip.LocalFile.open(zip_path)
    {:ok, unzip} = Unzip.new(zip_file)
    Unzip.file_stream!(unzip, file_name)
  end
end
