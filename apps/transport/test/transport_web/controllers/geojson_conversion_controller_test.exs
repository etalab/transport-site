defmodule TransportWeb.GeojsonConversionControllerTest do
  use ExUnit.Case
  alias TransportWeb.GeojsonConversionController
  doctest TransportWeb.GeojsonConversionController

  describe "test the gtfs to geojson conversion" do
    # NOTE: the :transport_tools tag is just a quick fix to completely skip the tests outside CI, until
    # we implement a better version of this, allowing to skip by default yet allow local runs
    # with specific versions (either compiled locally, or Docker-pulled)
    # See https://github.com/etalab/transport-site/issues/1820
    @tag :transport_tools
    test "check the conversion binary is accessible" do
      {:error, msg} = GeojsonConversionController.call_geojson_converter("")

      # this is the error msg we get when the binary file is not found
      assert msg != "rambo exited with 0"
    end

    @tag :transport_tools
    test "we can convert a gtfs" do
      {:ok, msg} = GeojsonConversionController.call_geojson_converter("#{__DIR__}/../../fixture/files/gtfs.zip")
      assert String.contains?(msg, "FeatureCollection")
    end
  end
end
