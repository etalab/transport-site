defmodule Transport.NeTEx.ToGeoJSON.Coordinates do
  @moduledoc """
  Parsing utilities for GML coordinate formats used in NeTEx files.

  GML uses lat/lon order while GeoJSON uses lon/lat order.
  This module handles the conversion between these formats.
  """

  @doc """
  Parses a GML posList string into GeoJSON coordinates.

  GML posList format: "lat lon lat lon ..." (space-separated, latitude first)
  GeoJSON format: [[lon, lat], [lon, lat], ...] (longitude first)

  ## Examples

      iex> Coordinates.parse_gml_pos_list("48.8566 2.3522 48.8600 2.3600")
      {:ok, [[2.3522, 48.8566], [2.36, 48.86]]}

      iex> Coordinates.parse_gml_pos_list("invalid")
      {:error, "Invalid coordinate value: invalid"}

      iex> Coordinates.parse_gml_pos_list("")
      {:ok, []}

  """
  @spec parse_gml_pos_list(String.t()) :: {:ok, [[number()]]} | {:error, String.t()}
  def parse_gml_pos_list(pos_list) when is_binary(pos_list) do
    pos_list
    |> String.trim()
    |> case do
      "" ->
        {:ok, []}

      trimmed ->
        trimmed
        |> String.split(~r/\s+/)
        |> parse_coordinate_pairs()
    end
  end

  @doc """
  Parses a GML coordinates string into GeoJSON coordinates.

  GML coordinates format: "lon,lat lon,lat ..." (comma-separated pairs, space between pairs)
  Note: Unlike posList, this format uses lon,lat order (same as GeoJSON).

  ## Examples

      iex> Coordinates.parse_gml_coordinates("2.3522,48.8566 2.3600,48.8600")
      {:ok, [[2.3522, 48.8566], [2.36, 48.86]]}

      iex> Coordinates.parse_gml_coordinates("")
      {:ok, []}

  """
  @spec parse_gml_coordinates(String.t()) :: {:ok, [[number()]]} | {:error, String.t()}
  def parse_gml_coordinates(coordinates) when is_binary(coordinates) do
    coordinates
    |> String.trim()
    |> case do
      "" ->
        {:ok, []}

      trimmed ->
        trimmed
        |> String.split(~r/\s+/)
        |> parse_coordinate_pairs_lon_lat()
    end
  end

  @doc """
  Parses a single latitude value.

  ## Examples

      iex> Coordinates.parse_latitude("48.8566")
      {:ok, 48.8566}

  """
  @spec parse_latitude(String.t()) :: {:ok, float()} | {:error, String.t()}
  def parse_latitude(lat_string) when is_binary(lat_string) do
    parse_float(String.trim(lat_string))
  end

  @doc """
  Parses a single longitude value.

  ## Examples

      iex> Coordinates.parse_longitude("2.3522")
      {:ok, 2.3522}

  """
  @spec parse_longitude(String.t()) :: {:ok, float()} | {:error, String.t()}
  def parse_longitude(lon_string) when is_binary(lon_string) do
    parse_float(String.trim(lon_string))
  end

  defp parse_coordinate_pairs_lon_lat(pairs) do
    Enum.reduce_while(pairs, {:ok, []}, fn pair, {:ok, acc} ->
      case parse_lon_lat_pair(pair) do
        {:ok, coord} -> {:cont, {:ok, acc ++ [coord]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp parse_lon_lat_pair(pair) do
    case String.split(pair, ",") do
      [lon_str, lat_str] ->
        with {:ok, lon} <- parse_float(lon_str),
             {:ok, lat} <- parse_float(lat_str) do
          {:ok, [lon, lat]}
        end

      _ ->
        {:error, "Invalid coordinate pair: #{pair}"}
    end
  end

  defp parse_coordinate_pairs(values) do
    if rem(length(values), 2) != 0 do
      {:error, "Odd number of coordinate values"}
    else
      values
      |> Enum.chunk_every(2)
      |> Enum.reduce_while({:ok, []}, fn [lat_str, lon_str], {:ok, acc} ->
        with {:ok, lat} <- parse_float(lat_str),
             {:ok, lon} <- parse_float(lon_str) do
          # Convert from GML lat/lon to GeoJSON lon/lat
          {:cont, {:ok, acc ++ [[lon, lat]]}}
        else
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp parse_float(string) do
    case Float.parse(string) do
      {value, ""} -> {:ok, value}
      {value, _rest} -> {:ok, value}
      :error -> {:error, "Invalid coordinate value: #{string}"}
    end
  end
end
