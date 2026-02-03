defmodule Transport.NeTEx do
  @moduledoc """
  A first implementation of on-the-fly NeTEx (zip) archive traversal.

  The current implementation is specialized into extracting `StopPlace`s, but the code
  will be generalized for other uses in a later PR.
  """
  require Logger

  @doc """
  Inside a zip archive opened with `Unzip`, parse a given file
  (pointed by `file_name`) and extract the stop places. The file
  is read in streaming fashion to save memory, but the stop places
  are stacked in a list (all in memory at once).
  """
  def read_stop_places(%Unzip{} = unzip, file_name) do
    parse_stream(unzip, file_name, Transport.NeTEx.StopPlacesStreamingParser)
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

  @doc """
  Inside a zip archive opened with `Unzip`, parse a given file
  (pointed by `file_name`) and extract the service calendars. The file
  is read in streaming fashion to save memory, but the stop places
  are stacked in a list (all in memory at once).
  """
  def read_service_calendars(%Unzip{} = unzip, file_name) do
    parse_stream(unzip, file_name, Transport.NeTEx.ServiceCalendarsStreamingParser)
  end

  @doc """
  Like read_service_calendars/2 but raises on errors.
  """
  def read_service_calendars!(%Unzip{} = unzip, file_name) do
    case read_service_calendars(unzip, file_name) do
      {:ok, service_calendars} -> service_calendars
      {:error, message} -> raise message
    end
  end

  def read_all_service_calendars(zip_file_name) do
    read_all(zip_file_name, &read_service_calendars/2)
  end

  def read_all_service_calendars!(zip_file_name) do
    read_all(zip_file_name, &read_service_calendars!/2)
  end

  @doc """
  Inside a zip archive opened with `Unzip`, parse a given file (pointed by
  `file_name`) and extract the calendars. The file is read in streaming fashion
  to save memory, but the stop places are stacked in a list (all in memory at
  once).
  """
  def read_calendars(%Unzip{} = unzip, file_name) do
    parse_stream(unzip, file_name, Transport.NeTEx.CalendarsStreamingParser)
  end

  @doc """
  Like read_calendars/2 but raises on errors.
  """
  def read_calendars!(%Unzip{} = unzip, file_name) do
    case read_calendars(unzip, file_name) do
      {:ok, service_calendars} -> service_calendars
      {:error, message} -> raise message
    end
  end

  def read_all_calendars(zip_file_name) do
    read_all(zip_file_name, &read_calendars/2)
  end

  def read_all_calendars!(zip_file_name) do
    read_all(zip_file_name, &read_calendars!/2)
  end

  @doc """
  Inside a zip archive opened with `Unzip`, parse a given file (pointed by
  `file_name`) and extract the type of frames. The file is read in streaming
  fashion to save memory, but the stop places are stacked in a list (all in
  memory at once).
  """
  def read_types_of_frames(%Unzip{} = unzip, file_name) do
    parse_stream(unzip, file_name, Transport.NeTEx.TypesOfFrameStreamingParser)
  end

  @doc """
  Like read_types_of_frames/2 but raises on errors.
  """
  def read_types_of_frames!(%Unzip{} = unzip, file_name) do
    case read_types_of_frames(unzip, file_name) do
      {:ok, types_of_frames} -> types_of_frames
      {:error, message} -> raise message
    end
  end

  def read_all_types_of_frames(zip_file_name) do
    read_all(zip_file_name, &read_types_of_frames/2)
  end

  def read_all_types_of_frames!(zip_file_name) do
    read_all(zip_file_name, &read_types_of_frames!/2)
  end

  defp parse_stream(unzip, file_name, parser) do
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
          |> Saxy.parse_stream(parser, parser.initial_state())

        case parsing_result do
          {:ok, state} -> {:ok, parser.unwrap_result(state)}
          {:error, exception} -> {:error, Exception.message(exception)}
          {:halt, _state, _rest} -> {:error, "SAX parsing interrupted unexpectedly."}
        end
    end
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

  defp with_zip_file_handle(zip_file_name, cb) do
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
end
