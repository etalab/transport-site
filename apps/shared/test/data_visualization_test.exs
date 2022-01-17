defmodule Transport.DataVisualizationTest do
  use ExUnit.Case
  alias Transport.DataVisualization
  doctest Transport.DataVisualization

  @validations %{
    "ExcessiveSpeed" => [
      %{
        "details" => "computed speed between the stops is 325858.52 km/h (5430975 m travelled in 60 seconds)",
        "geojson" => %{
          "features" => [
            %{
              "geometry" => %{
                "coordinates" => [2.449186, 48.796058],
                "type" => "Point"
              },
              "properties" => %{"id" => "near1", "name" => "Near1"},
              "type" => "Feature"
            },
            %{
              "geometry" => %{"coordinates" => [0.0, 0.0], "type" => "Point"},
              "properties" => %{"id" => "null", "name" => "Null Island"},
              "type" => "Feature"
            },
            %{
              "geometry" => %{
                "coordinates" => [[2.449186, 48.796058], [0.0, 0.0]],
                "type" => "LineString"
              },
              "properties" => %{
                "details" => "computed speed between the stops is 325858.52 km/h (5430975 m travelled in 60 seconds)"
              },
              "type" => "Feature"
            }
          ],
          "type" => "FeatureCollection"
        },
        "issue_type" => "ExcessiveSpeed",
        "object_id" => "near1",
        "object_name" => "Near1",
        "object_type" => "Stop",
        "related_objects" => [
          %{"id" => "null", "name" => "Null Island", "object_type" => "Stop"},
          %{"id" => "route1", "name" => "100", "object_type" => "Route"}
        ],
        "severity" => "Information"
      }
    ]
  }

  describe "test the data visualization creation" do
    test "simple data vis from validation only" do
      # We want to make sure the new method to create the data_vis
      # from the validation only has an output similar to the previous method
      data_vis = DataVisualization.validation_data_vis(@validations)

      assert data_vis |> Map.keys() == ["ExcessiveSpeed"]

      excessive_speed = data_vis |> Map.fetch!("ExcessiveSpeed")
      assert excessive_speed |> Map.keys() == ["geojson", "severity"]

      features = excessive_speed |> Map.fetch!("geojson") |> Map.fetch!("features")

      assert features |> Enum.frequencies_by(fn %{"geometry" => %{"type" => type}} -> type end) == %{
               "Point" => 2,
               "LineString" => 1
             }

      [line_string] = features |> Enum.filter(fn %{"geometry" => %{"type" => type}} -> type == "LineString" end)
      assert line_string["properties"]["details"] |> String.contains?("computed speed between the stops")
    end
  end
end
