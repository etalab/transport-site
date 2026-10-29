defmodule Transport.Jobs.GenericConverterTest do
  use ExUnit.Case, async: true
  alias Transport.Jobs.GenericConverter

  describe "maybe_sanitize_filename/2" do
    test "strips .zip and replaces dots with underscores for GeoJSON target" do
      assert GenericConverter.maybe_sanitize_filename("80960.20260914.181829.722495.zip.geojson", "geojson") ==
               "80960_20260914_181829_722495.geojson"
    end

    test "keeps simple filenames unchanged for GeoJSON target" do
      assert GenericConverter.maybe_sanitize_filename("simple.txt", "GeoJSON") == "simple.txt"
    end

    test "passes through non-GeoJSON targets unchanged" do
      assert GenericConverter.maybe_sanitize_filename("80960.20260914.zip.gtfs", "NeTEx") ==
               "80960.20260914.zip.gtfs"
    end
  end
end
