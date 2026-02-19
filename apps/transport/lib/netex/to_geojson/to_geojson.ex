defmodule Transport.NeTEx.ToGeoJSON do
  @moduledoc """
  Converts NeTEx archives (ZIP containing XML files) to GeoJSON FeatureCollection.

  Supports extracting:
  - StopPlace (stops) → Points
  - Quay (platforms/quays) → Points
  - ServiceLink (route paths) → LineStrings

  ## Usage

      # Convert a full archive
      {:ok, geojson} = Transport.NeTEx.ToGeoJSON.convert_archive("/path/to/netex.zip")

      # Filter by element types
      {:ok, geojson} = Transport.NeTEx.ToGeoJSON.convert_archive(path, types: [:stop_places, :quays])

      # Convert XML directly
      {:ok, geojson} = Transport.NeTEx.ToGeoJSON.convert_xml(xml_string)

  """

  require Logger

  alias Transport.NeTEx.ToGeoJSON.GeoJSONBuilder
  alias Transport.NeTEx.ToGeoJSON.QuayParser
  alias Transport.NeTEx.ToGeoJSON.ServiceLinkParser

  @type element_type :: :stop_places | :quays | :service_links
  @type option :: {:types, [element_type()]}

  @all_types [:stop_places, :quays, :service_links]

  @doc """
  Converts a NeTEx ZIP archive to a GeoJSON FeatureCollection.

  ## Options

  - `:types` - List of element types to extract. Defaults to all types.
    Available types: `:stop_places`, `:quays`, `:service_links`

  ## Examples

      {:ok, geojson} = Transport.NeTEx.ToGeoJSON.convert_archive("/path/to/netex.zip")

      {:ok, geojson} = Transport.NeTEx.ToGeoJSON.convert_archive(path, types: [:stop_places])

  """
  @spec convert_archive(String.t(), [option()]) :: {:ok, map()} | {:error, String.t()}
  def convert_archive(zip_path, opts \\ []) do
    types = Keyword.get(opts, :types, @all_types)

    Transport.NeTEx.with_zip_file_handle(zip_path, fn unzip ->
      features =
        unzip
        |> Unzip.list_entries()
        |> Enum.flat_map(fn metadata ->
          extract_features_from_entry(unzip, metadata.file_name, types)
        end)

      {:ok, GeoJSONBuilder.feature_collection(features)}
    end)
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Converts NeTEx XML content directly to a GeoJSON FeatureCollection.

  ## Options

  - `:types` - List of element types to extract. Defaults to all types.

  ## Examples

      {:ok, geojson} = Transport.NeTEx.ToGeoJSON.convert_xml(xml_content)

  """
  @spec convert_xml(String.t(), [option()]) :: {:ok, map()} | {:error, String.t()}
  def convert_xml(xml, opts \\ []) do
    types = Keyword.get(opts, :types, @all_types)

    features = extract_features_from_xml(xml, types)
    {:ok, GeoJSONBuilder.feature_collection(features)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp extract_features_from_entry(unzip, file_name, types) do
    extension = Path.extname(file_name)

    cond do
      String.ends_with?(file_name, "/") ->
        []

      String.downcase(extension) != ".xml" ->
        []

      true ->
        Logger.debug("Processing #{file_name} for GeoJSON conversion")

        stream =
          unzip
          |> Unzip.file_stream!(file_name)
          |> Stream.map(&IO.iodata_to_binary/1)

        extract_features_from_stream(stream, types)
    end
  end

  defp extract_features_from_stream(stream, types) do
    # We need to read the full content since we parse with multiple parsers
    xml = Enum.join(stream)
    extract_features_from_xml(xml, types)
  end

  defp extract_features_from_xml(xml, types) do
    features = []

    features =
      if :stop_places in types do
        features ++ extract_stop_places(xml)
      else
        features
      end

    features =
      if :quays in types do
        features ++ extract_quays(xml)
      else
        features
      end

    features =
      if :service_links in types do
        features ++ extract_service_links(xml)
      else
        features
      end

    features
  end

  defp extract_stop_places(xml) do
    state = %{
      current_stop_place: nil,
      capture: false,
      current_tree: [],
      stop_places: [],
      callback: fn state ->
        state |> update_in([:stop_places], &(&1 ++ [state.current_stop_place]))
      end
    }

    case Saxy.parse_string(xml, Transport.NeTEx.StopPlacesStreamingParser, state) do
      {:ok, final_state} ->
        final_state.stop_places
        |> Enum.map(fn stop -> Map.put(stop, :type, :stop_place) end)
        |> Enum.map(&GeoJSONBuilder.stop_to_feature/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_quays(xml) do
    case QuayParser.parse(xml) do
      {:ok, quays} ->
        quays
        |> Enum.map(&GeoJSONBuilder.stop_to_feature/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_service_links(xml) do
    case ServiceLinkParser.parse(xml) do
      {:ok, links} ->
        links
        |> Enum.map(&GeoJSONBuilder.service_link_to_feature/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end
end
