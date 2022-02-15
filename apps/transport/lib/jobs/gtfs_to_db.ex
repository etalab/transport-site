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
          location_type: r |> Map.fetch!("location_type")
        }
      end)
      |> Stream.chunk_every(1000)
      |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsStops, chunk) end)
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

    DB.Repo.transaction(fn ->
      file_stream
      |> to_stream_of_maps()
      |> Stream.map(fn r ->
        %{
          data_import_id: data_import_id,
          service_id: r |> Map.fetch!("service_id"),
          monday: r |> Map.fetch!("monday") |> String.to_integer(),
          tuesday: r |> Map.fetch!("tuesday") |> String.to_integer(),
          wednesday: r |> Map.fetch!("wednesday") |> String.to_integer(),
          thursday: r |> Map.fetch!("thursday") |> String.to_integer(),
          friday: r |> Map.fetch!("friday") |> String.to_integer(),
          saturday: r |> Map.fetch!("saturday") |> String.to_integer(),
          sunday: r |> Map.fetch!("sunday") |> String.to_integer(),
          start_date: r |> Map.fetch!("start_date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date(),
          end_date: r |> Map.fetch!("end_date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date()
        }
      end)
      |> Stream.chunk_every(1000)
      |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsCalendar, chunk) end)
      |> Stream.run()
    end)
  end

  def fill_stop_times_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)
    file_stream = Transport.Unzip.S3File.get_file_stream("stop_times.txt", filename, bucket_name)

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
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsStopTimes, chunk) end)
        |> Stream.run()
      end,
      timeout: 240_000
    )
  end

  def cast_binary_to_interval(s) do
    %{"hours" => hours, "minutes" => minutes, "seconds" => seconds} =
      Regex.named_captures(~r/(?<hours>[0-9]+):(?<minutes>[0-9]+):(?<seconds>[0-9]+)/, s)

    hours = hours |> String.to_integer()
    minutes = minutes |> String.to_integer()
    seconds = seconds |> String.to_integer()

    # this is what EctoInterval is able to cast into a Postgrex.Interval
    %{
      "secs" => hours * 60 * 60 + minutes * 60 + seconds,
      "days" => 0,
      "months" => 0
    }
  end

  def fill_calendar_dates_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)
    file_stream = Transport.Unzip.S3File.get_file_stream("calendar_dates.txt", filename, bucket_name)

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
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsCalendarDates, chunk) end)
        |> Stream.run()
      end,
      timeout: 240_000
    )
  end

  def fill_trips_from_resource_history(resource_history_id, data_import_id) do
    %{payload: %{"filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)
    file_stream = Transport.Unzip.S3File.get_file_stream("trips.txt", filename, bucket_name)

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
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsTrips, chunk) end)
        |> Stream.run()
      end,
      timeout: 240_000
    )
  end
end
