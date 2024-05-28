defmodule Transport.NeTEx do
  require Logger

  @doc """
  Inside a zip archive opened with `Unzip`, parse a given file
  (pointed by `file_name`) and extract the stop places. The file
  is read in streaming fashion to save memory, but the stop places
  are stacked in a list (all in memory at once).
  """
  def read_stop_places(%Unzip{} = unzip, file_name) do
    unless (ext = Path.extname(file_name)) == ".xml" do
      raise "Insupported file extension (#{ext}) for file #{file_name}"
    end

    {:ok, state} =
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

    state.stop_places
  end

  @doc """
  Open the zip file pointed by `zip_file_name` and return an `Unzip.LocalFile` struct.
  """
  def with_zip_file_handle(zip_file_name, cb) do
    zip_file = Unzip.LocalFile.open(zip_file_name)

    try do
      {:ok, unzip} = Unzip.new(zip_file)
      cb.(unzip)
    after
      Unzip.LocalFile.close(zip_file)
    end
  end

  @doc """
  A higher level method, recommended for general use. Given a NeTEx zip archive stored
  on disk,
  """
  def read_all_stop_places(zip_file_name) do
    with_zip_file_handle(zip_file_name, fn unzip ->
      unzip
      |> Unzip.list_entries()
      |> Enum.map(fn metadata ->
        Logger.info("Processing #{metadata.file_name}")

        {
          metadata.file_name,
          read_stop_places(unzip, metadata.file_name)
        }
      end)
    end)
  end
end
