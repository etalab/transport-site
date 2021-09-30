defmodule TransportWeb.GeojsonConversionControllerTest do
  use ExUnit.Case
  alias TransportWeb.GeojsonConversionController
  doctest TransportWeb.GeojsonConversionController

  describe "test the gtfs to geojson conversion" do
    test "check the conversion binary is accessible" do
      {:error, msg} = GeojsonConversionController.call_geojson_converter("")

      # this is the error msg we get when the binary file is not found
      assert msg != "rambo exited with 0"
    end

    test "we can convert a gtfs" do
      {:ok, msg} = GeojsonConversionController.call_geojson_converter("#{__DIR__}/../../fixture/files/gtfs.zip")
      assert String.contains?(msg, "FeatureCollection")
    end
  end
end
