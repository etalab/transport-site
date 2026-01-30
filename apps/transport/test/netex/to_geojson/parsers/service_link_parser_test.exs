defmodule Transport.NeTEx.ToGeoJSON.ServiceLinkParserTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.ToGeoJSON.ServiceLinkParser

  describe "parse/1" do
    test "parses a ServiceLink with all fields and posList coordinates" do
      xml = """
      <ServiceLink id="FR:LINK:001">
        <Name>Route Express</Name>
        <FromPointRef ref="stop_1"/>
        <ToPointRef ref="stop_2"/>
        <projections>
          <LinkProjection>
            <gml:LineString>
              <gml:posList>48.85 2.35 48.86 2.36 48.87 2.37</gml:posList>
            </gml:LineString>
          </LinkProjection>
        </projections>
      </ServiceLink>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)

      assert link == %{
               id: "FR:LINK:001",
               name: "Route Express",
               from_point_ref: "stop_1",
               to_point_ref: "stop_2",
               coordinates: [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]
             }
    end

    test "parses a ServiceLink with gml:coordinates format" do
      xml = """
      <ServiceLink id="link_1">
        <Name>Route A</Name>
        <gml:LineString>
          <gml:coordinates>2.35,48.85 2.36,48.86</gml:coordinates>
        </gml:LineString>
      </ServiceLink>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)

      assert link.id == "link_1"
      assert link.name == "Route A"
      assert link.coordinates == [[2.35, 48.85], [2.36, 48.86]]
    end

    test "parses a ServiceLink with minimal fields" do
      xml = """
      <ServiceLink id="link_1">
        <Name>Simple Link</Name>
      </ServiceLink>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)

      assert link == %{
               id: "link_1",
               name: "Simple Link"
             }
    end

    test "parses multiple ServiceLinks" do
      xml = """
      <root>
        <ServiceLink id="link_1">
          <Name>Route 1</Name>
          <FromPointRef ref="a"/>
          <ToPointRef ref="b"/>
        </ServiceLink>
        <ServiceLink id="link_2">
          <Name>Route 2</Name>
          <FromPointRef ref="b"/>
          <ToPointRef ref="c"/>
        </ServiceLink>
      </root>
      """

      assert {:ok, links} = ServiceLinkParser.parse(xml)
      assert length(links) == 2

      [link1, link2] = links
      assert link1.id == "link_1"
      assert link1.from_point_ref == "a"
      assert link1.to_point_ref == "b"

      assert link2.id == "link_2"
      assert link2.from_point_ref == "b"
      assert link2.to_point_ref == "c"
    end

    test "handles negative coordinates in posList" do
      xml = """
      <ServiceLink id="link_1">
        <gml:LineString>
          <gml:posList>43.669 -0.919 43.670 -0.920</gml:posList>
        </gml:LineString>
      </ServiceLink>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)
      assert link.coordinates == [[-0.919, 43.669], [-0.92, 43.67]]
    end

    test "handles whitespace in posList" do
      xml = """
      <ServiceLink id="link_1">
        <gml:LineString>
          <gml:posList>
            48.85    2.35
            48.86    2.36
          </gml:posList>
        </gml:LineString>
      </ServiceLink>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)
      assert link.coordinates == [[2.35, 48.85], [2.36, 48.86]]
    end

    test "ignores non-ServiceLink elements" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
        </StopPlace>
        <ServiceLink id="link_1">
          <Name>Link</Name>
        </ServiceLink>
      </root>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)
      assert link.id == "link_1"
    end

    test "returns empty list for XML without ServiceLinks" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
        </StopPlace>
      </root>
      """

      assert {:ok, []} = ServiceLinkParser.parse(xml)
    end

    test "does not include coordinates if less than 2 points" do
      xml = """
      <ServiceLink id="link_1">
        <gml:LineString>
          <gml:posList>48.85 2.35</gml:posList>
        </gml:LineString>
      </ServiceLink>
      """

      assert {:ok, [link]} = ServiceLinkParser.parse(xml)
      refute Map.has_key?(link, :coordinates)
    end
  end
end
