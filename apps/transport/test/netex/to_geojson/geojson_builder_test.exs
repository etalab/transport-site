defmodule Transport.NeTEx.ToGeoJSON.GeoJSONBuilderTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.ToGeoJSON.GeoJSONBuilder

  describe "feature_collection/1" do
    test "creates an empty FeatureCollection" do
      assert GeoJSONBuilder.feature_collection([]) == %{
               "type" => "FeatureCollection",
               "features" => []
             }
    end

    test "creates a FeatureCollection with features" do
      features = [
        %{"type" => "Feature", "geometry" => %{}, "properties" => %{}}
      ]

      assert GeoJSONBuilder.feature_collection(features) == %{
               "type" => "FeatureCollection",
               "features" => features
             }
    end
  end

  describe "point_feature/3" do
    test "creates a Point feature with id" do
      result = GeoJSONBuilder.point_feature([2.3522, 48.8566], %{"name" => "Paris"}, "stop_1")

      assert result == %{
               "type" => "Feature",
               "id" => "stop_1",
               "geometry" => %{
                 "type" => "Point",
                 "coordinates" => [2.3522, 48.8566]
               },
               "properties" => %{"name" => "Paris"}
             }
    end

    test "creates a Point feature without id" do
      result = GeoJSONBuilder.point_feature([2.3522, 48.8566], %{"name" => "Paris"})

      assert result == %{
               "type" => "Feature",
               "geometry" => %{
                 "type" => "Point",
                 "coordinates" => [2.3522, 48.8566]
               },
               "properties" => %{"name" => "Paris"}
             }
    end

    test "handles negative coordinates" do
      result = GeoJSONBuilder.point_feature([-0.919, 43.669], %{}, "stop_1")

      assert result["geometry"]["coordinates"] == [-0.919, 43.669]
    end
  end

  describe "line_string_feature/3" do
    test "creates a LineString feature with id" do
      coords = [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]

      result =
        GeoJSONBuilder.line_string_feature(coords, %{"name" => "Route A"}, "link_1")

      assert result == %{
               "type" => "Feature",
               "id" => "link_1",
               "geometry" => %{
                 "type" => "LineString",
                 "coordinates" => coords
               },
               "properties" => %{"name" => "Route A"}
             }
    end

    test "creates a LineString feature without id" do
      coords = [[2.35, 48.85], [2.36, 48.86]]
      result = GeoJSONBuilder.line_string_feature(coords, %{})

      refute Map.has_key?(result, "id")
      assert result["geometry"]["type"] == "LineString"
    end
  end

  describe "stop_to_feature/1" do
    test "converts a complete stop to a Point feature" do
      stop = %{
        id: "FR:STOP:001",
        name: "Gare Centrale",
        latitude: 48.8566,
        longitude: 2.3522,
        public_code: "GC",
        type: :stop_place
      }

      result = GeoJSONBuilder.stop_to_feature(stop)

      assert result == %{
               "type" => "Feature",
               "id" => "FR:STOP:001",
               "geometry" => %{
                 "type" => "Point",
                 "coordinates" => [2.3522, 48.8566]
               },
               "properties" => %{
                 "netex_id" => "FR:STOP:001",
                 "name" => "Gare Centrale",
                 "public_code" => "GC",
                 "type" => :stop_place
               }
             }
    end

    test "converts a minimal stop (only id and coordinates)" do
      stop = %{id: "stop_1", latitude: 45.0, longitude: 3.0}

      result = GeoJSONBuilder.stop_to_feature(stop)

      assert result["id"] == "stop_1"
      assert result["geometry"]["coordinates"] == [3.0, 45.0]
      assert result["properties"] == %{"netex_id" => "stop_1"}
    end

    test "returns nil for stop without latitude" do
      stop = %{id: "stop_1", longitude: 3.0}
      assert GeoJSONBuilder.stop_to_feature(stop) == nil
    end

    test "returns nil for stop without longitude" do
      stop = %{id: "stop_1", latitude: 45.0}
      assert GeoJSONBuilder.stop_to_feature(stop) == nil
    end

    test "returns nil for stop with nil coordinates" do
      stop = %{id: "stop_1", latitude: nil, longitude: nil}
      assert GeoJSONBuilder.stop_to_feature(stop) == nil
    end
  end

  describe "service_link_to_feature/1" do
    test "converts a complete service link to a LineString feature" do
      link = %{
        id: "FR:LINK:001",
        name: "Route Express",
        from_point_ref: "stop_1",
        to_point_ref: "stop_2",
        coordinates: [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]
      }

      result = GeoJSONBuilder.service_link_to_feature(link)

      assert result == %{
               "type" => "Feature",
               "id" => "FR:LINK:001",
               "geometry" => %{
                 "type" => "LineString",
                 "coordinates" => [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]
               },
               "properties" => %{
                 "netex_id" => "FR:LINK:001",
                 "name" => "Route Express",
                 "from_point_ref" => "stop_1",
                 "to_point_ref" => "stop_2"
               }
             }
    end

    test "converts a minimal service link" do
      link = %{
        id: "link_1",
        coordinates: [[2.35, 48.85], [2.36, 48.86]]
      }

      result = GeoJSONBuilder.service_link_to_feature(link)

      assert result["id"] == "link_1"
      assert result["geometry"]["type"] == "LineString"
      assert result["properties"] == %{"netex_id" => "link_1"}
    end

    test "returns nil for link without coordinates" do
      link = %{id: "link_1", name: "Route"}
      assert GeoJSONBuilder.service_link_to_feature(link) == nil
    end

    test "returns nil for link with empty coordinates" do
      link = %{id: "link_1", coordinates: []}
      assert GeoJSONBuilder.service_link_to_feature(link) == nil
    end

    test "returns nil for link with single coordinate" do
      link = %{id: "link_1", coordinates: [[2.35, 48.85]]}
      assert GeoJSONBuilder.service_link_to_feature(link) == nil
    end
  end
end
