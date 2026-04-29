defmodule Transport.NeTEx.ToGeoJSON.GeoJSONBuilder do
  @moduledoc """
  Utility functions for building GeoJSON structures.

  Provides functions to create GeoJSON FeatureCollection, Point features,
  and LineString features from parsed NeTEx data.
  """

  @doc """
  Creates a GeoJSON FeatureCollection from a list of features.

  ## Examples

      iex> GeoJSONBuilder.feature_collection([])
      %{"type" => "FeatureCollection", "features" => []}

  """
  @spec feature_collection([map()]) :: map()
  def feature_collection(features) when is_list(features) do
    %{
      "type" => "FeatureCollection",
      "features" => features
    }
  end

  @doc """
  Creates a GeoJSON Point feature.

  Coordinates should be provided as [longitude, latitude] (GeoJSON order).

  ## Examples

      iex> GeoJSONBuilder.point_feature([2.3522, 48.8566], %{"name" => "Paris"}, "stop_1")
      %{
        "type" => "Feature",
        "id" => "stop_1",
        "geometry" => %{"type" => "Point", "coordinates" => [2.3522, 48.8566]},
        "properties" => %{"name" => "Paris"}
      }

  """
  @spec point_feature([number()], map(), String.t() | nil) :: map()
  def point_feature(coordinates, properties, id \\ nil)

  def point_feature([lon, lat] = coordinates, properties, id)
      when is_number(lon) and is_number(lat) and is_map(properties) do
    feature = %{
      "type" => "Feature",
      "geometry" => %{
        "type" => "Point",
        "coordinates" => coordinates
      },
      "properties" => properties
    }

    maybe_add_id(feature, id)
  end

  @doc """
  Creates a GeoJSON LineString feature.

  Coordinates should be provided as a list of [longitude, latitude] pairs (GeoJSON order).

  ## Examples

      iex> coords = [[2.35, 48.85], [2.36, 48.86]]
      iex> GeoJSONBuilder.line_string_feature(coords, %{"name" => "Route A"}, "link_1")
      %{
        "type" => "Feature",
        "id" => "link_1",
        "geometry" => %{"type" => "LineString", "coordinates" => [[2.35, 48.85], [2.36, 48.86]]},
        "properties" => %{"name" => "Route A"}
      }

  """
  @spec line_string_feature([[number()]], map(), String.t() | nil) :: map()
  def line_string_feature(coordinates, properties, id \\ nil)

  def line_string_feature(coordinates, properties, id)
      when is_list(coordinates) and is_map(properties) do
    feature = %{
      "type" => "Feature",
      "geometry" => %{
        "type" => "LineString",
        "coordinates" => coordinates
      },
      "properties" => properties
    }

    maybe_add_id(feature, id)
  end

  @doc """
  Converts a parsed stop (StopPlace or Quay) to a GeoJSON Point feature.

  The input map should contain at minimum :id, and optionally :name, :latitude, :longitude,
  :public_code, and :type.

  Returns nil if latitude or longitude are missing.

  ## Examples

      iex> stop = %{id: "stop_1", name: "Gare", latitude: 48.8566, longitude: 2.3522}
      iex> GeoJSONBuilder.stop_to_feature(stop)
      %{
        "type" => "Feature",
        "id" => "stop_1",
        "geometry" => %{"type" => "Point", "coordinates" => [2.3522, 48.8566]},
        "properties" => %{"name" => "Gare", "netex_id" => "stop_1"}
      }

  """
  @spec stop_to_feature(map()) :: map() | nil
  def stop_to_feature(%{latitude: lat, longitude: lon} = stop)
      when is_number(lat) and is_number(lon) do
    properties =
      %{"netex_id" => stop[:id]}
      |> maybe_put("name", stop[:name])
      |> maybe_put("public_code", stop[:public_code])
      |> maybe_put("type", stop[:type])

    point_feature([lon, lat], properties, stop[:id])
  end

  def stop_to_feature(_stop), do: nil

  @doc """
  Converts a parsed ServiceLink to a GeoJSON LineString feature.

  The input map should contain :id, :coordinates (list of [lon, lat] pairs),
  and optionally :name, :from_point_ref, :to_point_ref.

  Returns nil if coordinates are missing or empty.

  ## Examples

      iex> link = %{id: "link_1", name: "Route", coordinates: [[2.35, 48.85], [2.36, 48.86]]}
      iex> GeoJSONBuilder.service_link_to_feature(link)
      %{
        "type" => "Feature",
        "id" => "link_1",
        "geometry" => %{"type" => "LineString", "coordinates" => [[2.35, 48.85], [2.36, 48.86]]},
        "properties" => %{"name" => "Route", "netex_id" => "link_1"}
      }

  """
  @spec service_link_to_feature(map()) :: map() | nil
  def service_link_to_feature(%{coordinates: coords} = link)
      when is_list(coords) and length(coords) >= 2 do
    properties =
      %{"netex_id" => link[:id]}
      |> maybe_put("name", link[:name])
      |> maybe_put("from_point_ref", link[:from_point_ref])
      |> maybe_put("to_point_ref", link[:to_point_ref])

    line_string_feature(coords, properties, link[:id])
  end

  def service_link_to_feature(_link), do: nil

  defp maybe_add_id(feature, nil), do: feature
  defp maybe_add_id(feature, id), do: Map.put(feature, "id", id)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
