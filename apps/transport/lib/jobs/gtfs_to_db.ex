defmodule Transport.Jobs.GtfsToDB do
  @moduledoc """
  Get the content of a GTFS ResourceHistory, store it in the DB
  """

  def fill_stop_from_resource_history(resource_history_id) do
    %{payload: %{"uuid" => uuid, "filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)

    file_stream = Transport.Unzip.S3File.get_file_stream("stops.txt", filename, bucket_name)

    # we should try to stream directly to Ecto instead of saving the file locally...
    temp_file = "#{uuid}_stops.txt"

    try do
      file_stream |> Stream.into(File.stream!(temp_file)) |> Stream.run()

      DB.Repo.transaction(fn ->
        File.stream!(temp_file, [:trim_bom])
        |> CSV.decode!(headers: true)
        |> Stream.map(fn r ->
          %{
            stop_id: Map.fetch!(r, "stop_id"),
            stop_name: Map.fetch!(r, "stop_name"),
            stop_lat: Map.fetch!(r, "stop_lat") |> String.to_float(),
            stop_lon: Map.fetch!(r, "stop_lon") |> String.to_float(),
            location_type: Map.fetch!(r, "location_type")
          }
        end)
        |> Stream.chunk_every(1000)
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsStops, chunk) end)
        |> Stream.run()
      end)
    after
      File.rm(temp_file)
    end
  end

  def fill_calendar_from_resource_history(resource_history_id) do
    %{payload: %{"uuid" => uuid, "filename" => filename}} = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)
    bucket_name = Transport.S3.bucket_name(:history)

    file_stream = Transport.Unzip.S3File.get_file_stream("calendar.txt", filename, bucket_name)

    # we should try to stream directly to Ecto instead of saving the file locally...
    temp_file = "#{uuid}_calendar.txt"

    try do
      file_stream |> Stream.into(File.stream!(temp_file)) |> Stream.run()

      DB.Repo.transaction(fn ->
        File.stream!(temp_file, [:trim_bom])
        |> CSV.decode!(headers: true)
        |> Stream.map(fn r ->
          %{
            service_id: Map.fetch!(r, "service_id"),
            monday: Map.fetch!(r, "monday") |> String.to_integer(),
            tuesday: Map.fetch!(r, "tuesday") |> String.to_integer(),
            wednesday: Map.fetch!(r, "wednesday") |> String.to_integer(),
            thursday: Map.fetch!(r, "thursday") |> String.to_integer(),
            friday: Map.fetch!(r, "friday") |> String.to_integer(),
            saturday: Map.fetch!(r, "saturday") |> String.to_integer(),
            sunday: Map.fetch!(r, "sunday") |> String.to_integer(),
            start_date: Map.fetch!(r, "start_date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date(),
            end_date: Map.fetch!(r, "end_date") |> Timex.parse!("{YYYY}{0M}{0D}") |> NaiveDateTime.to_date()
          }
        end)
        |> Stream.chunk_every(1000)
        |> Stream.each(fn chunk -> DB.Repo.insert_all(DB.GtfsCalendar, chunk) end)
        |> Stream.run()
      end)
    after
      File.rm(temp_file)
    end
  end
end
