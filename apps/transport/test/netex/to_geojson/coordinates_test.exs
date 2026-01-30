defmodule Transport.NeTEx.ToGeoJSON.CoordinatesTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.ToGeoJSON.Coordinates

  describe "parse_gml_pos_list/1" do
    test "parses a simple posList with two coordinates" do
      assert {:ok, [[2.3522, 48.8566], [2.36, 48.86]]} ==
               Coordinates.parse_gml_pos_list("48.8566 2.3522 48.86 2.36")
    end

    test "parses a posList with multiple coordinates" do
      pos_list = "48.85 2.35 48.86 2.36 48.87 2.37"

      assert {:ok, [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]} ==
               Coordinates.parse_gml_pos_list(pos_list)
    end

    test "handles negative coordinates" do
      assert {:ok, [[-0.919, 43.669]]} ==
               Coordinates.parse_gml_pos_list("43.669 -0.919")
    end

    test "handles whitespace variations" do
      assert {:ok, [[2.35, 48.85], [2.36, 48.86]]} ==
               Coordinates.parse_gml_pos_list("  48.85   2.35   48.86  2.36  ")
    end

    test "handles newlines and tabs" do
      pos_list = "48.85\t2.35\n48.86\t2.36"

      assert {:ok, [[2.35, 48.85], [2.36, 48.86]]} ==
               Coordinates.parse_gml_pos_list(pos_list)
    end

    test "returns empty list for empty string" do
      assert {:ok, []} == Coordinates.parse_gml_pos_list("")
    end

    test "returns empty list for whitespace-only string" do
      assert {:ok, []} == Coordinates.parse_gml_pos_list("   ")
    end

    test "returns error for odd number of values" do
      assert {:error, "Odd number of coordinate values"} ==
               Coordinates.parse_gml_pos_list("48.85 2.35 48.86")
    end

    test "returns error for invalid numeric values" do
      assert {:error, "Invalid coordinate value: abc"} ==
               Coordinates.parse_gml_pos_list("48.85 abc")
    end
  end

  describe "parse_gml_coordinates/1" do
    test "parses a simple coordinates string" do
      assert {:ok, [[2.3522, 48.8566], [2.36, 48.86]]} ==
               Coordinates.parse_gml_coordinates("2.3522,48.8566 2.36,48.86")
    end

    test "parses multiple coordinate pairs" do
      coords = "2.35,48.85 2.36,48.86 2.37,48.87"

      assert {:ok, [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]} ==
               Coordinates.parse_gml_coordinates(coords)
    end

    test "handles negative coordinates" do
      assert {:ok, [[-0.919, 43.669]]} ==
               Coordinates.parse_gml_coordinates("-0.919,43.669")
    end

    test "handles whitespace variations" do
      assert {:ok, [[2.35, 48.85], [2.36, 48.86]]} ==
               Coordinates.parse_gml_coordinates("  2.35,48.85   2.36,48.86  ")
    end

    test "returns empty list for empty string" do
      assert {:ok, []} == Coordinates.parse_gml_coordinates("")
    end

    test "returns error for invalid pair format" do
      assert {:error, "Invalid coordinate pair: 2.35"} ==
               Coordinates.parse_gml_coordinates("2.35")
    end

    test "returns error for invalid numeric values" do
      assert {:error, "Invalid coordinate value: abc"} ==
               Coordinates.parse_gml_coordinates("abc,48.85")
    end
  end

  describe "parse_latitude/1" do
    test "parses a valid latitude" do
      assert {:ok, 48.8566} == Coordinates.parse_latitude("48.8566")
    end

    test "parses a negative latitude" do
      assert {:ok, -33.8688} == Coordinates.parse_latitude("-33.8688")
    end

    test "handles whitespace" do
      assert {:ok, 48.8566} == Coordinates.parse_latitude("  48.8566  ")
    end

    test "returns error for invalid value" do
      assert {:error, "Invalid coordinate value: invalid"} ==
               Coordinates.parse_latitude("invalid")
    end
  end

  describe "parse_longitude/1" do
    test "parses a valid longitude" do
      assert {:ok, 2.3522} == Coordinates.parse_longitude("2.3522")
    end

    test "parses a negative longitude" do
      assert {:ok, -0.919} == Coordinates.parse_longitude("-0.919")
    end

    test "handles whitespace" do
      assert {:ok, 2.3522} == Coordinates.parse_longitude("  2.3522  ")
    end

    test "returns error for invalid value" do
      assert {:error, "Invalid coordinate value: invalid"} ==
               Coordinates.parse_longitude("invalid")
    end
  end
end
