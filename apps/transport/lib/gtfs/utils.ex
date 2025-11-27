defmodule Transport.GTFS.Utils do
  @moduledoc """
  Some helpers for handling GTFS archives.
  """

  @doc """
  iex> get_position(%{"stop_id" => ""}, "stop_lat")
  nil
  iex> get_position(%{"stop_lat" => "42.1337"}, "stop_lat")
  42.1337
  """
  def get_position(record, field) do
    Map.get(record, field, "") |> convert_text_to_float()
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

  @doc """
  Variant of csv_get_with_default/3 that raises if a mandatory column is missing.
  """
  def csv_get_with_default!(map, field, default_value, mandatory_column \\ true) do
    value = if mandatory_column, do: Map.fetch!(map, field), else: Map.get(map, field)

    case value do
      nil -> default_value
      "" -> default_value
      v -> v
    end
  end

  @doc """
  iex> csv_get_with_default(%{}, "field", 0)
  0
  iex> csv_get_with_default(%{"other_field" => 1}, "field", 0)
  0
  iex> csv_get_with_default(%{"field" => 2, "other_field" => 1}, "field", 0)
  2
  iex> csv_get_with_default(%{"field" => "", "other_field" => 1}, "field", 0)
  0
  """
  def csv_get_with_default(map, field, default_value) do
    value = Map.get(map, field)

    case value do
      nil -> default_value
      "" -> default_value
      v -> v
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
end
