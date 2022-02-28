defmodule Transport.Jobs.GtfsToDB do
  @moduledoc """
  Get the content of a GTFS ResourceHistory, store it in the DB
  """

  def import_gtfs_from_resource_history(resource_history_id) do
    %{id: data_import_id} = %DB.DataImport{resource_history_id: 200} |> DB.Repo.insert!()

    fill_stops_from_resource_history(resource_history_id, data_import_id)
    fill_stop_times_from_resource_history(resource_history_id, data_import_id)
    fill_calendar_from_resource_history(resource_history_id, data_import_id)
    fill_calendar_dates_from_resource_history(resource_history_id, data_import_id)
    fill_trips_from_resource_history(resource_history_id, data_import_id)
  end

  def fill_stops_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)

    file_stream = Transport.Unzip.S3File.get_file_stream("stops.txt", filename, bucket_name)
    stops_stream_insert(file_stream, data_import_id)
  end

  def stops_stream_insert(file_stream, data_import_id) do
    DB.Repo.transaction(fn ->
      file_stream
      |> to_stream_of_maps()
      # the map is reshaped for Ecto's needs
      |> Stream.map(fn r ->
        %{
          data_import_id: data_import_id,
          stop_id: r |> Map.fetch!("stop_id"),
          stop_name: r |> Map.fetch!("stop_name"),
          stop_lat: r |> Map.fetch!("stop_lat") |> String.to_float(),
          stop_lon: r |> Map.fetch!("stop_lon") |> String.to_float(),
          location_type: r |> Map.fetch!("location_type") |> String.to_integer()
        }
      end)
      |> Stream.chunk_every(1000)
      |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GTFS.Stops, chunk) end)
      |> Stream.run()
    end)
  end

  @doc """
  Transform the stream outputed by Unzip to a stream of maps, each map
  corresponding to a row from the CSV.
  """
  def to_stream_of_maps(file_stream) do
    file_stream
    # transform the stream to a stream of binaries
    |> Stream.map(fn c -> IO.iodata_to_binary(c) end)
    # stream line by line
    |> NimbleCSV.RFC4180.to_line_stream()
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    # transform the stream to a stream of maps %{column_name1: value1, ...}
    |> Stream.transform([], fn r, acc ->
      if acc == [] do
        {%{}, r |> Enum.map(fn h -> h |> String.replace_prefix("\uFEFF", "") end)}
      else
        {[acc |> Enum.zip(r) |> Enum.into(%{})], acc}
      end
    end)
  end

  def fill_calendar_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)

    file_stream = Transport.Unzip.S3File.get_file_stream("calendar.txt", filename, bucket_name)

    calendar_stream_insert(file_stream, data_import_id)
  end

  def calendar_stream_insert(file_stream, data_import_id) do
    DB.Repo.transaction(fn ->
      file_stream
      |> to_stream_of_maps()
      |> Stream.map(fn r ->
        res = %{
          data_import_id: data_import_id,
          service_id: r |> Map.fetch!("service_id"),
          monday: monday = r |> Map.fetch!("monday") |> String.to_integer(),
          tuesday: tuesday = r |> Map.fetch!("tuesday") |> String.to_integer(),
          wednesday: wednesday = r |> Map.fetch!("wednesday") |> String.to_integer(),
          thursday: thursday = r |> Map.fetch!("thursday") |> String.to_integer(),
          friday: friday = r |> Map.fetch!("friday") |> String.to_integer(),
          saturday: saturday = r |> Map.fetch!("saturday") |> String.to_integer(),
          sunday: sunday = r |> Map.fetch!("sunday") |> String.to_integer(),
          start_date: r |> Map.fetch!("start_date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date(),
          end_date: r |> Map.fetch!("end_date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date()
        }

        res
        |> Map.put(:days, get_dow_array([monday, tuesday, wednesday, thursday, friday, saturday, sunday]))
      end)
      |> Stream.chunk_every(1000)
      |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GTFS.Calendar, chunk) end)
      |> Stream.run()
    end)
  end

  @doc """
   Takes values (0 or 1) for each day, return an array with the days of weeks having their value equal to 1

   iex> get_dow_array([1,0,1,0,0,0,1])
   [1,3,7]
  """
  def get_dow_array([_monday, _tuesday, _wednesday, _thursday, _friday, _saturday, _sunday] = dows) do
    dows
    |> Enum.with_index()
    |> Enum.filter(&(elem(&1, 0) == 1))
    |> Enum.map(&(elem(&1, 1) + 1))
  end

  def fill_stop_times_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)
    file_stream = Transport.Unzip.S3File.get_file_stream("stop_times.txt", filename, bucket_name)
    stop_times_stream_insert(file_stream, data_import_id)
  end

  def stop_times_stream_insert(file_stream, data_import_id) do
    DB.Repo.transaction(
      fn ->
        file_stream
        |> to_stream_of_maps()
        |> Stream.map(fn r ->
          %{
            data_import_id: data_import_id,
            trip_id: r |> Map.fetch!("trip_id"),
            arrival_time: r |> Map.fetch!("arrival_time") |> cast_binary_to_interval(),
            departure_time: r |> Map.fetch!("departure_time") |> cast_binary_to_interval(),
            stop_id: r |> Map.fetch!("stop_id"),
            stop_sequence: r |> Map.fetch!("stop_sequence") |> String.to_integer()
          }
        end)
        |> Stream.chunk_every(1000)
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GTFS.StopTimes, chunk) end)
        |> Stream.run()
      end,
      timeout: 240_000
    )
  end

  @doc """
   Parse a binary containing a GTFS style time, and convert it to a struct ready to be inserted as an interval in the DB

   iex> cast_binary_to_interval("01:02:03")
   %{secs: 3723, days: 0, months: 0}
  """
  def cast_binary_to_interval(s) do
    %{"hours" => hours, "minutes" => minutes, "seconds" => seconds} =
      Regex.named_captures(~r/(?<hours>[0-9]+):(?<minutes>[0-9]+):(?<seconds>[0-9]+)/, s)

    hours = hours |> String.to_integer()
    minutes = minutes |> String.to_integer()
    seconds = seconds |> String.to_integer()

    # this is what EctoInterval is able to cast into a Postgrex.Interval
    %{
      secs: hours * 60 * 60 + minutes * 60 + seconds,
      days: 0,
      months: 0
    }
  end

  def fill_calendar_dates_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)
    file_stream = Transport.Unzip.S3File.get_file_stream("calendar_dates.txt", filename, bucket_name)
    calendar_dates_stream_insert(file_stream, data_import_id)
  end

  def calendar_dates_stream_insert(file_stream, data_import_id) do
    DB.Repo.transaction(
      fn ->
        file_stream
        |> to_stream_of_maps()
        |> Stream.map(fn r ->
          %{
            data_import_id: data_import_id,
            service_id: r |> Map.fetch!("service_id"),
            date: r |> Map.fetch!("date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date(),
            exception_type: r |> Map.fetch!("exception_type") |> String.to_integer()
          }
        end)
        |> Stream.chunk_every(1000)
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GTFS.CalendarDates, chunk) end)
        |> Stream.run()
      end,
      timeout: 240_000
    )
  end

  def fill_trips_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)
    file_stream = Transport.Unzip.S3File.get_file_stream("trips.txt", filename, bucket_name)
    trips_stream_insert(file_stream, data_import_id)
  end

  def trips_stream_insert(file_stream, data_import_id) do
    DB.Repo.transaction(
      fn ->
        file_stream
        |> to_stream_of_maps()
        |> Stream.map(fn r ->
          %{
            data_import_id: data_import_id,
            service_id: r |> Map.fetch!("service_id"),
            route_id: r |> Map.fetch!("route_id"),
            trip_id: r |> Map.fetch!("trip_id")
          }
        end)
        |> Stream.chunk_every(1000)
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GTFS.Trips, chunk) end)
        |> Stream.run()
      end,
      timeout: 240_000
    )
  end
end
