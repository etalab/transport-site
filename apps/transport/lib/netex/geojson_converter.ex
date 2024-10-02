defmodule Transport.NeTEx.GeoJSONConverter do
  @moduledoc """
  A first converter to extract stop places and display it as a GeoJSON.
  """

  @doc """
  Reads a NeTEx zip archive stored on disk, and returns a GeoJSON.
  """
  @spec convert(binary()) :: binary()
  def convert(zip_file_name) do
    {:ok, result} =
      zip_file_name
      |> collect_stop_places()
      |> to_geojson_feature_collection()
      |> Jason.encode()

    result
  end

  def collect_stop_places(zip_file_name) do
    zip_file_name
    |> Transport.NeTEx.read_all_stop_places()
    |> Enum.flat_map(&keep_stop_places_with_location/1)
  end

  @spec keep_stop_places_with_location({binary(), list()}) :: list()
  defp keep_stop_places_with_location({_filename, stop_places}) do
    Enum.filter(stop_places, &has_location?/1)
  end

  @spec has_location?(map()) :: boolean()
  defp has_location?(stop_place) do
    Map.has_key?(stop_place, :latitude) && Map.has_key?(stop_place, :longitude)
  end

  defp to_geojson_feature_collection(features) do
    %{
      type: "FeatureCollection",
      features: Enum.map(features, &to_geojson_feature/1)
    }
  end

  defp to_geojson_feature(%{latitude: latitude, longitude: longitude, name: name}) do
    %{
      type: "Feature",
      geometry: %{
        type: "Point",
        coordinates: [longitude, latitude]
      },
      properties: %{
        name: name
      }
    }
  end

  defp to_geojson_feature(%{id: id, latitude: latitude, longitude: longitude}),
    do: to_geojson_feature(%{latitude: latitude, longitude: longitude, name: id})
end
