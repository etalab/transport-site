defmodule Transport.NeTEx.ToGeoJSON.QuayParserTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.ToGeoJSON.QuayParser

  describe "parse/1" do
    test "parses a simple Quay with all fields" do
      xml = """
      <Quay id="FR:QUAY:001">
        <Name>Quai A</Name>
        <PublicCode>A</PublicCode>
        <Centroid>
          <Location>
            <Latitude>48.8566</Latitude>
            <Longitude>2.3522</Longitude>
          </Location>
        </Centroid>
      </Quay>
      """

      assert {:ok, [quay]} = QuayParser.parse(xml)

      assert quay == %{
               id: "FR:QUAY:001",
               name: "Quai A",
               public_code: "A",
               latitude: 48.8566,
               longitude: 2.3522,
               type: :quay
             }
    end

    test "parses a Quay with minimal fields" do
      xml = """
      <Quay id="quay_1">
        <Name>Platform 1</Name>
      </Quay>
      """

      assert {:ok, [quay]} = QuayParser.parse(xml)

      assert quay == %{
               id: "quay_1",
               name: "Platform 1",
               type: :quay
             }
    end

    test "parses multiple Quays" do
      xml = """
      <root>
        <Quay id="quay_1">
          <Name>Platform 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </Quay>
        <Quay id="quay_2">
          <Name>Platform 2</Name>
          <PublicCode>2</PublicCode>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      assert {:ok, quays} = QuayParser.parse(xml)
      assert length(quays) == 2

      [quay1, quay2] = quays
      assert quay1.id == "quay_1"
      assert quay1.name == "Platform 1"
      assert quay1.latitude == 48.85
      assert quay1.longitude == 2.35

      assert quay2.id == "quay_2"
      assert quay2.name == "Platform 2"
      assert quay2.public_code == "2"
    end

    test "handles negative coordinates" do
      xml = """
      <Quay id="quay_1">
        <Centroid>
          <Location>
            <Latitude>43.669</Latitude>
            <Longitude>-0.919</Longitude>
          </Location>
        </Centroid>
      </Quay>
      """

      assert {:ok, [quay]} = QuayParser.parse(xml)
      assert quay.latitude == 43.669
      assert quay.longitude == -0.919
    end

    test "ignores non-Quay elements" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Platform</Name>
        </Quay>
      </root>
      """

      assert {:ok, [quay]} = QuayParser.parse(xml)
      assert quay.id == "quay_1"
    end

    test "returns empty list for XML without Quays" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
        </StopPlace>
      </root>
      """

      assert {:ok, []} = QuayParser.parse(xml)
    end

    test "handles deeply nested Quays" do
      xml = """
      <root>
        <frame>
          <members>
            <StopPlace id="stop_1">
              <quays>
                <Quay id="quay_1">
                  <Name>Nested Quay</Name>
                </Quay>
              </quays>
            </StopPlace>
          </members>
        </frame>
      </root>
      """

      assert {:ok, [quay]} = QuayParser.parse(xml)
      assert quay.id == "quay_1"
      assert quay.name == "Nested Quay"
    end
  end
end
