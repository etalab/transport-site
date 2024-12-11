defmodule Transport.Registry.GTFS do
  alias Transport.Registry.Model.DataSource
  alias Transport.Registry.Model.Stop
  alias Transport.Registry.Model.StopIdentifier

  @behaviour Transport.Registry.Extractor
  @doc """
  Extract stops from GTFS ressource.
  """
  def extract_from_archive(archive) do
    archive
    |> file_stream!()
    |> to_stream_of_maps()
    |> Stream.map(fn r ->
      %Stop{
        main_id: %StopIdentifier{id: Map.fetch!(r, "stop_id"), type: :main},
        display_name: Map.fetch!(r, "stop_name"),
        latitude: Map.fetch!(r, "stop_lat") |> convert_text_to_float(),
        longitude: Map.fetch!(r, "stop_lon") |> convert_text_to_float(),
        projection: :utm_wgs84,
        stop_type: r |> csv_get_with_default!("location_type", "0", false) |> to_stop_type()
      }
    end)

    {:ok, []}
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

  @doc """
   Convert textual values to float.

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
    input |> String.trim() |> Decimal.new() |> Decimal.to_float()
  end

  defp to_stop_type("0"), do: :quay
  defp to_stop_type("1"), do: :stop
  defp to_stop_type(_), do: :other

  defp file_stream!(archive) do
    zip_file = Unzip.LocalFile.open(archive)

    {:ok, unzip} = Unzip.new(zip_file)

    Unzip.file_stream!(unzip, "stops.txt")
  end

  defp csv_get_with_default!(map, field, default_value, mandatory_column \\ true) do
    value = if mandatory_column, do: Map.fetch!(map, field), else: Map.get(map, field)

    case value do
      nil -> default_value
      "" -> default_value
      v -> v
    end
  end
end
