defmodule Transport.Registry.GTFS do
  @moduledoc """
  Implementation of a stop extractor for GTFS resources.
  """

  alias Transport.Registry.Model.Stop
  alias Transport.Registry.Model.StopIdentifier
  alias Transport.Registry.Result

  alias Transport.GTFS.Utils

  require Logger

  @behaviour Transport.Registry.Extractor
  @doc """
  Extract stops from GTFS ressource.
  """
  def extract_from_archive(data_source_id, archive) do
    case file_stream(archive) do
      {:error, error} ->
        Logger.error(error)
        Result.error(error)

      {:ok, {content, zip_file}} ->
        Logger.debug("Valid Zip archive")

        try do
          content
          |> Utils.to_stream_of_maps()
          |> Stream.flat_map(&handle_stop(data_source_id, &1))
          |> Enum.to_list()
          |> Result.ok()
        after
          Unzip.LocalFile.close(zip_file)
        rescue
          e in NimbleCSV.ParseError ->
            e
            |> Exception.message()
            |> Result.error()
        end
    end
  end

  defp handle_stop(data_source_id, record) do
    latitude = Utils.fetch_position(record, "stop_lat")
    longitude = Utils.fetch_position(record, "stop_lon")

    if latitude != nil && longitude != nil do
      [
        %Stop{
          main_id: %StopIdentifier{id: Map.fetch!(record, "stop_id"), type: :main},
          display_name: Map.fetch!(record, "stop_name"),
          latitude: latitude,
          longitude: longitude,
          projection: :utm_wgs84,
          stop_type: record |> Utils.csv_get_with_default("location_type", "0") |> to_stop_type(),
          data_source_format: :gtfs,
          data_source_id: data_source_id
        }
      ]
    else
      []
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
          content = unzip |> Unzip.file_stream!("stops.txt")
          # The zip_file is kept open for now as it's consumed later.
          Result.ok({content, zip_file})
        else
          Unzip.LocalFile.close(zip_file)
          Result.error("Missing stops.txt in #{archive}")
        end

      {:error, error} ->
        Result.error("Error while unzipping archive #{archive}: #{error}")
    end
  end

  defp has_stops?(unzip) do
    unzip
    |> Unzip.list_entries()
    |> Enum.any?(&entry_of_name?("stops.txt", &1))
  end

  defp entry_of_name?(name, %Unzip.Entry{file_name: file_name}) do
    file_name == name
  end
end
