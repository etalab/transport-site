defmodule Transport.NeTEx.ToGeoJSONTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.ToGeoJSON

  defmodule ZipCreator do
    @spec create!(String.t(), [{String.t(), binary()}]) :: no_return()
    def create!(zip_filename, file_data) do
      {:ok, ^zip_filename} =
        :zip.create(
          zip_filename,
          file_data
          |> Enum.map(fn {name, content} -> {name |> to_charlist(), content} end)
        )
    end
  end

  describe "convert_xml/1" do
    test "converts StopPlaces to Point features" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Gare Centrale</Name>
          <Centroid>
            <Location>
              <Latitude>48.8566</Latitude>
              <Longitude>2.3522</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml)

      assert geojson["type"] == "FeatureCollection"
      assert length(geojson["features"]) == 1

      [feature] = geojson["features"]
      assert feature["type"] == "Feature"
      assert feature["id"] == "stop_1"
      assert feature["geometry"]["type"] == "Point"
      assert feature["geometry"]["coordinates"] == [2.3522, 48.8566]
      assert feature["properties"]["name"] == "Gare Centrale"
      assert feature["properties"]["type"] == :stop_place
    end

    test "converts Quays to Point features" do
      xml = """
      <root>
        <Quay id="quay_1">
          <Name>Platform 1</Name>
          <PublicCode>1</PublicCode>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml)

      assert length(geojson["features"]) == 1

      [feature] = geojson["features"]
      assert feature["id"] == "quay_1"
      assert feature["geometry"]["type"] == "Point"
      assert feature["properties"]["name"] == "Platform 1"
      assert feature["properties"]["public_code"] == "1"
      assert feature["properties"]["type"] == :quay
    end

    test "converts ServiceLinks to LineString features" do
      xml = """
      <root>
        <ServiceLink id="link_1">
          <Name>Route A</Name>
          <FromPointRef ref="stop_1"/>
          <ToPointRef ref="stop_2"/>
          <gml:LineString>
            <gml:posList>48.85 2.35 48.86 2.36 48.87 2.37</gml:posList>
          </gml:LineString>
        </ServiceLink>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml)

      assert length(geojson["features"]) == 1

      [feature] = geojson["features"]
      assert feature["id"] == "link_1"
      assert feature["geometry"]["type"] == "LineString"
      assert feature["geometry"]["coordinates"] == [[2.35, 48.85], [2.36, 48.86], [2.37, 48.87]]
      assert feature["properties"]["name"] == "Route A"
      assert feature["properties"]["from_point_ref"] == "stop_1"
      assert feature["properties"]["to_point_ref"] == "stop_2"
    end

    test "combines all element types" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Quay 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
        <ServiceLink id="link_1">
          <Name>Link 1</Name>
          <gml:LineString>
            <gml:posList>48.85 2.35 48.86 2.36</gml:posList>
          </gml:LineString>
        </ServiceLink>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml)

      assert length(geojson["features"]) == 3

      types = Enum.map(geojson["features"], & &1["geometry"]["type"])
      assert "Point" in types
      assert "LineString" in types
    end

    test "filters by types option - stop_places only" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Quay</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml, types: [:stop_places])

      assert length(geojson["features"]) == 1
      assert hd(geojson["features"])["id"] == "stop_1"
    end

    test "filters by types option - quays only" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Quay</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml, types: [:quays])

      assert length(geojson["features"]) == 1
      assert hd(geojson["features"])["id"] == "quay_1"
    end

    test "filters by types option - multiple types" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Quay</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
        <ServiceLink id="link_1">
          <Name>Link</Name>
          <gml:LineString>
            <gml:posList>48.85 2.35 48.86 2.36</gml:posList>
          </gml:LineString>
        </ServiceLink>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml, types: [:stop_places, :quays])

      assert length(geojson["features"]) == 2

      ids = Enum.map(geojson["features"], & &1["id"])
      assert "stop_1" in ids
      assert "quay_1" in ids
      refute "link_1" in ids
    end

    test "skips elements without coordinates" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop without coords</Name>
        </StopPlace>
        <StopPlace id="stop_2">
          <Name>Stop with coords</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
      </root>
      """

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml)

      assert length(geojson["features"]) == 1
      assert hd(geojson["features"])["id"] == "stop_2"
    end

    test "returns empty FeatureCollection for XML without supported elements" do
      xml = "<root><SomeOtherElement/></root>"

      assert {:ok, geojson} = ToGeoJSON.convert_xml(xml)

      assert geojson == %{
               "type" => "FeatureCollection",
               "features" => []
             }
    end
  end

  describe "convert_archive/1" do
    test "converts a ZIP archive with multiple XML files" do
      xml1 = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
      </root>
      """

      xml2 = """
      <root>
        <Quay id="quay_1">
          <Name>Quay 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      tmp_file = System.tmp_dir!() |> Path.join("netex-geojson-#{Ecto.UUID.generate()}.zip")
      ZipCreator.create!(tmp_file, [{"stops.xml", xml1}, {"quays.xml", xml2}])

      assert {:ok, geojson} = ToGeoJSON.convert_archive(tmp_file)

      assert geojson["type"] == "FeatureCollection"
      assert length(geojson["features"]) == 2

      ids = Enum.map(geojson["features"], & &1["id"])
      assert "stop_1" in ids
      assert "quay_1" in ids

      File.rm!(tmp_file)
    end

    test "filters by types option" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Quay 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      tmp_file = System.tmp_dir!() |> Path.join("netex-geojson-#{Ecto.UUID.generate()}.zip")
      ZipCreator.create!(tmp_file, [{"data.xml", xml}])

      assert {:ok, geojson} = ToGeoJSON.convert_archive(tmp_file, types: [:quays])

      assert length(geojson["features"]) == 1
      assert hd(geojson["features"])["id"] == "quay_1"

      File.rm!(tmp_file)
    end

    test "skips non-XML files" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
      </root>
      """

      tmp_file = System.tmp_dir!() |> Path.join("netex-geojson-#{Ecto.UUID.generate()}.zip")
      ZipCreator.create!(tmp_file, [{"data.xml", xml}, {"readme.txt", "Some text"}])

      assert {:ok, geojson} = ToGeoJSON.convert_archive(tmp_file)

      assert length(geojson["features"]) == 1

      File.rm!(tmp_file)
    end

    test "skips directories" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
      </root>
      """

      tmp_file = System.tmp_dir!() |> Path.join("netex-geojson-#{Ecto.UUID.generate()}.zip")
      ZipCreator.create!(tmp_file, [{"subdir/data.xml", xml}])

      assert {:ok, geojson} = ToGeoJSON.convert_archive(tmp_file)

      # Should still find the XML in the subdirectory
      assert length(geojson["features"]) == 1

      File.rm!(tmp_file)
    end
  end

  describe "Transport.NeTEx.to_geojson/1 facade" do
    test "delegates to convert_archive" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop 1</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
      </root>
      """

      tmp_file = System.tmp_dir!() |> Path.join("netex-geojson-#{Ecto.UUID.generate()}.zip")
      ZipCreator.create!(tmp_file, [{"data.xml", xml}])

      assert {:ok, geojson} = Transport.NeTEx.to_geojson(tmp_file)

      assert geojson["type"] == "FeatureCollection"
      assert length(geojson["features"]) == 1

      File.rm!(tmp_file)
    end

    test "accepts types option" do
      xml = """
      <root>
        <StopPlace id="stop_1">
          <Name>Stop</Name>
          <Centroid>
            <Location>
              <Latitude>48.85</Latitude>
              <Longitude>2.35</Longitude>
            </Location>
          </Centroid>
        </StopPlace>
        <Quay id="quay_1">
          <Name>Quay</Name>
          <Centroid>
            <Location>
              <Latitude>48.86</Latitude>
              <Longitude>2.36</Longitude>
            </Location>
          </Centroid>
        </Quay>
      </root>
      """

      tmp_file = System.tmp_dir!() |> Path.join("netex-geojson-#{Ecto.UUID.generate()}.zip")
      ZipCreator.create!(tmp_file, [{"data.xml", xml}])

      assert {:ok, geojson} = Transport.NeTEx.to_geojson(tmp_file, types: [:stop_places])

      assert length(geojson["features"]) == 1
      assert hd(geojson["features"])["id"] == "stop_1"

      File.rm!(tmp_file)
    end
  end
end
