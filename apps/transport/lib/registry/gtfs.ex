defmodule Transport.Registry.GTFS do
  @moduledoc """
  Implementation of a stop extractor for GTFS resources.
  """

  alias Transport.Registry.Model.Stop
  alias Transport.Registry.Model.StopIdentifier

  require Logger

  @behaviour Transport.Registry.Extractor
  @doc """
  Extract stops from GTFS ressource.
  """
  def extract_from_archive(archive) do
    case file_stream(archive) do
      {:error, error} ->
        Logger.error(error)
        {:error, error}

      {:ok, content} ->
        Logger.debug("Valid Zip archive")

        stops =
          content
          |> to_stream_of_maps()
          |> Stream.flat_map(&handle_stop/1)
          |> Enum.to_list()

        {:ok, stops}
    end
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

  defp handle_stop(record) do
    latitude = fetch_position(record, "stop_lat")
    longitude = fetch_position(record, "stop_lon")

    if latitude != nil && longitude != nil do
      [
        %Stop{
          main_id: %StopIdentifier{id: Map.fetch!(record, "stop_id"), type: :main},
          display_name: Map.fetch!(record, "stop_name"),
          latitude: latitude,
          longitude: longitude,
          projection: :utm_wgs84,
          stop_type: record |> csv_get_with_default!("location_type", "0") |> to_stop_type()
        }
      ]
    else
      []
    end
  end

  defp fetch_position(record, field) do
    Map.fetch!(record, field) |> convert_text_to_float()
  end

  @doc """
   Convert textual values to float.

   iex> convert_text_to_float("")
   nil
   iex> convert_text_to_float("0")
   0.0
   iex> convert_text_to_float("0.0")
   0.0
   iex> convert_text_to_float("12.7")
   12.7
   iex> convert_text_to_float("-12.7")
   -12.7
   iex> convert_text_to_float("   -48.7    ")
   -48.7
  """
  def convert_text_to_float(input) do
    if input |> String.trim() != "" do
      input |> String.trim() |> Decimal.new() |> Decimal.to_float()
    else
      nil
    end
  end

  defp to_stop_type("0"), do: :quay
  defp to_stop_type("1"), do: :stop
  defp to_stop_type(_), do: :other

  defp file_stream(archive) do
    zip_file = Unzip.LocalFile.open(archive)

    case Unzip.new(zip_file) do
      {:ok, unzip} ->
        if has_stops?(unzip) do
          {:ok, Unzip.file_stream!(unzip, "stops.txt")}
        else
          {:error, "Missing stops.txt in #{archive}"}
        end

      {:error, error} ->
        {:error, "Error while unzipping archive #{archive}: #{error}"}
    end
  end

  defp has_stops?(unzip) do
    Unzip.list_entries(unzip)
    |> Enum.any?(&entry_of_name?("stops.txt", &1))
  end

  defp entry_of_name?(name, %Unzip.Entry{file_name: file_name}) do
    file_name == name
  end

  defp csv_get_with_default!(map, field, default_value) do
    value = Map.get(map, field)

    case value do
      nil -> default_value
      "" -> default_value
      v -> v
    end
  end
end
