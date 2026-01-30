defmodule Transport.NeTEx do
  @moduledoc """
  A first implementation of on-the-fly NeTEx (zip) archive traversal.

  The current implementation is specialized into extracting `StopPlace`s, but the code
  will be generalized for other uses in a later PR.

  Also provides conversion to GeoJSON via `to_geojson/1` and `to_geojson/2`.
  """
  require Logger

  @doc """
  Converts a NeTEx ZIP archive to a GeoJSON FeatureCollection.

  This is a convenience facade for `Transport.NeTEx.ToGeoJSON.convert_archive/2`.

  ## Options

  - `:types` - List of element types to extract. Defaults to all types.
    Available types: `:stop_places`, `:quays`, `:service_links`

  ## Examples

      {:ok, geojson} = Transport.NeTEx.to_geojson("/path/to/netex.zip")

      {:ok, geojson} = Transport.NeTEx.to_geojson(path, types: [:stop_places, :quays])

  """
  @spec to_geojson(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  defdelegate to_geojson(zip_path, opts \\ []), to: Transport.NeTEx.ToGeoJSON, as: :convert_archive

  @doc """
  Inside a zip archive opened with `Unzip`, parse a given file
  (pointed by `file_name`) and extract the stop places. The file
  is read in streaming fashion to save memory, but the stop places
  are stacked in a list (all in memory at once).
  """
  def read_stop_places(%Unzip{} = unzip, file_name) do
    extension = Path.extname(file_name)

    cond do
      # Entry names ending with a slash `/` are directories. Skip them.
      # https://github.com/akash-akya/unzip/blob/689a1ca7a134ab2aeb79c8c4f8492d61fa3e09a0/lib/unzip.ex#L69
      String.ends_with?(file_name, "/") ->
        {:ok, []}

      extension |> String.downcase() == ".zip" ->
        {:error, "Insupported zip inside zip for file #{file_name}"}

      extension |> String.downcase() != ".xml" ->
        {:error, "Insupported file extension (#{extension}) for file #{file_name}"}

      true ->
        parsing_result =
          unzip
          |> Unzip.file_stream!(file_name)
          |> Stream.map(&IO.iodata_to_binary(&1))
          |> Saxy.parse_stream(Transport.NeTEx.StopPlacesStreamingParser, %{
            capture: false,
            current_tree: [],
            stop_places: [],
            callback: fn state ->
              state |> update_in([:stop_places], &(&1 ++ [state.current_stop_place]))
            end
          })

        case parsing_result do
          {:ok, state} -> {:ok, state.stop_places}
          {:error, exception} -> {:error, Exception.message(exception)}
          {:halt, _state, _rest} -> {:error, "SAX parsing interrupted unexpectedly."}
        end
    end
  end

  @doc """
  Like read_stop_places/2 but raises on errors.
  """
  def read_stop_places!(%Unzip{} = unzip, file_name) do
    case read_stop_places(unzip, file_name) do
      {:ok, stop_places} -> stop_places
      {:error, message} -> raise message
    end
  end

  @doc """
  Open the zip file pointed by `zip_file_name` and return an `Unzip.LocalFile` struct.
  """
  def with_zip_file_handle(zip_file_name, cb) do
    zip_file = Unzip.LocalFile.open(zip_file_name)

    try do
      case Unzip.new(zip_file) do
        {:ok, unzip} ->
          cb.(unzip)

        {:error, message} ->
          Logger.error("Error while reading #{zip_file_name}: #{message}")
          []
      end
    after
      Unzip.LocalFile.close(zip_file)
    end
  end

  @doc """
  A higher level method, recommended for general use. Given a NeTEx zip archive stored
  on disk, return the list of `StopPlace`s per file contained in the archive.

  See tests for actual output. Will be refactored soonish.
  """
  def read_all_stop_places(zip_file_name) do
    read_all(zip_file_name, &read_stop_places/2)
  end

  @doc """
  Like read_all_stop_places/1 but raises on error.
  """
  def read_all_stop_places!(zip_file_name) do
    read_all(zip_file_name, &read_stop_places!/2)
  end

  defp read_all(zip_file_name, reader) do
    with_zip_file_handle(zip_file_name, fn unzip ->
      unzip
      |> Unzip.list_entries()
      |> Enum.map(fn metadata ->
        Logger.debug("Processing #{metadata.file_name}")

        {
          metadata.file_name,
          reader.(unzip, metadata.file_name)
        }
      end)
    end)
  end
end
