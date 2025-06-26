defmodule Transport.Registry.NeTEx do
  @moduledoc """
  Implementation of a stop extractor for NeTEx resources.
  """

  alias Transport.Registry.Model.Stop
  alias Transport.Registry.Model.StopIdentifier
  alias Transport.Registry.Result

  require Logger

  @behaviour Transport.Registry.Extractor
  @doc """
  Extract stops from a NeTEx archive.
  """
  def extract_from_archive(data_source_id, archive) do
    archive
    |> Transport.NeTEx.read_all_stop_places()
    |> Enum.flat_map(&process_stop_places(data_source_id, &1))
    |> Result.ok()
  end

  defp process_stop_places(data_source_id, {_filename, {:ok, stop_places}}) do
    stop_places |> Enum.map(&to_stop(data_source_id, &1)) |> Result.cat_results()
  end

  defp process_stop_places(_data_source_id, {filename, {:error, message}}) do
    Logger.error("Processing of #{filename}, error: #{message}")
    []
  end

  defp to_stop(data_source_id, %{id: id, name: name, latitude: latitude, longitude: longitude}) do
    %Stop{
      main_id: StopIdentifier.main(id),
      display_name: name,
      latitude: latitude,
      longitude: longitude,
      data_source_format: :netex,
      data_source_id: data_source_id
    }
    |> Result.ok()
  end

  defp to_stop(_data_source_id, incomplete_record) do
    expected_keys = MapSet.new(~w(id name latitude longitude))
    keys = MapSet.new(Map.keys(incomplete_record))

    missing_keys = MapSet.difference(expected_keys, keys) |> Enum.to_list()

    message = "Can't build stop, missing keys: #{inspect(missing_keys)}"

    Logger.error(message)
    Result.error(message)
  end
end
