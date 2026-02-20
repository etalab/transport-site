defmodule Transport.Validators.NeTEx.MetadataExtractorTest do
  use ExUnit.Case, async: true
  import Transport.TmpFile

  alias Transport.Validators.NeTEx.MetadataExtractor

  describe "invalid zip archives" do
    test "empty or corrupt file should return empty result silently" do
      for content <- ["", "illegal zip content"] do
        {true, logs} =
          ExUnit.CaptureLog.with_log(fn ->
            with_tmp_file(content, fn filepath ->
              assert %{
                       "no_validity_dates" => true,
                       "networks" => [],
                       "modes" => [],
                       "stats" => %{
                         "routes_count" => 0,
                         "quays_count" => 0,
                         "stop_places_count" => 0
                       }
                     } ==
                       MetadataExtractor.extract(filepath)
            end)
          end)

        assert logs =~ "Invalid zip file, missing EOCD record"
      end
    end

    test "empty valid ZIP archive" do
      ZipCreator.with_tmp_zip([], fn filepath ->
        assert %{
                 "no_validity_dates" => true,
                 "networks" => [],
                 "modes" => [],
                 "stats" => %{
                   "routes_count" => 0,
                   "quays_count" => 0,
                   "stop_places_count" => 0
                 }
               } ==
                 MetadataExtractor.extract(filepath)
      end)
    end
  end

  describe "validity dates" do
    test "simple NeTEx archive" do
      calendar_content = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex" xmlns:gis="http://www.opengis.net/gml/3.2" xmlns:siri="http://www.siri.org.uk/siri" version="1.1:FR-NETEX_CALENDRIER-2.2">
          <PublicationTimestamp>2025-07-29T09:34:55Z</PublicationTimestamp>
          <ParticipantRef>DIGO</ParticipantRef>
          <dataObjects>
            <GeneralFrame version="any" id="DIGO:GeneralFrame:NETEX_CALENDRIER-20250729093455Z:LOC">
              <ValidBetween>
                <FromDate>2025-07-05T00:00:00</FromDate>
                <ToDate>2025-08-31T23:59:59</ToDate>
              </ValidBetween>
            </GeneralFrame>
          </dataObjects>
        </PublicationDelivery>
      """

      ZipCreator.with_tmp_zip([{"resource.xml", calendar_content}] |> in_sub_directory(), fn filepath ->
        assert %{
                 "start_date" => "2025-07-05",
                 "end_date" => "2025-08-31",
                 "networks" => [],
                 "modes" => [],
                 "stats" => %{
                   "routes_count" => 0,
                   "quays_count" => 0,
                   "stop_places_count" => 0
                 }
               } ==
                 MetadataExtractor.extract(filepath)
      end)
    end

    test "validity dates from dayTypes" do
      service_calendar_content = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex" xmlns:siri="http://www.siri.org.uk/siri" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" xsi:schemaLocation="http://www.netex.org.uk/netex ../../../xsd/NeTEx_publication.xsd">
          <dataObjects>
            <ServiceCalendarFrame version="any" id="LIO:ServiceCalendarFrame:0:LOC">
              <TypeOfFrameRef ref="FR:TypeOfFrame:NETEX_CALENDRIER:"/>
              <dayTypes>
                <DayType version="any" id="LIO:DayType:6e68183c42604e2d0f67">
                  <ValidBetween>
                    <FromDate>2025-11-03T00:00:00</FromDate>
                    <ToDate>2025-11-15T00:00:00</ToDate>
                  </ValidBetween>
                  <Name>2025-11-03 → 2025-11-15</Name>
                </DayType>
                <DayType version="any" id="LIO:DayType:5d21656b7c1e4d2b0557">
                  <ValidBetween>
                    <FromDate>2025-11-21T00:00:00</FromDate>
                    <ToDate>2025-11-28T00:00:00</ToDate>
                  </ValidBetween>
                  <Name>2025-11-21 → 2025-11-28</Name>
                </DayType>
              </dayTypes>
            </ServiceCalendarFrame>
          </dataObjects>
        </PublicationDelivery>
      """

      ZipCreator.with_tmp_zip([{"resource.xml", service_calendar_content}] |> in_sub_directory(), fn filepath ->
        assert %{
                 "start_date" => "2025-11-03",
                 "end_date" => "2025-11-28",
                 "networks" => [],
                 "modes" => [],
                 "stats" => %{
                   "routes_count" => 0,
                   "quays_count" => 0,
                   "stop_places_count" => 0
                 }
               } ==
                 MetadataExtractor.extract(filepath)
      end)
    end
  end

  describe "networks" do
    test "standard use case" do
      multiple_networks = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
          <PublicationTimestamp>2026-02-02T15:45:04Z</PublicationTimestamp>
          <ParticipantRef>FR1_OFFRE</ParticipantRef>
          <dataObjects>
            <GeneralFrame id="FR:GeneralFrame:NETEX_COMMUN:LOC" version="1.09:FR-NETEX-2.1-1.0">
              <members>
                <Network>
                  <Name>Réseau Urbain</Name>
                </Network>
                <Network>
                  <Name>Réseau Régional</Name>
                </Network>
                <Line>
                  <TransportMode>bus</TransportMode>
                </Line>
                <Line>
                  <TransportMode>ferry</TransportMode>
                </Line>
                <Line>
                  <TransportMode>bus</TransportMode>
                </Line>
              </members>
            </GeneralFrame>
          </dataObjects>
        </PublicationDelivery>
      """

      ZipCreator.with_tmp_zip([{"network.xml", multiple_networks}] |> in_sub_directory(), fn filepath ->
        assert %{
                 "no_validity_dates" => true,
                 "networks" => ["Réseau Urbain", "Réseau Régional"],
                 "modes" => ["bus", "ferry"],
                 "stats" => %{
                   "routes_count" => 0,
                   "quays_count" => 0,
                   "stop_places_count" => 0
                 }
               } ==
                 MetadataExtractor.extract(filepath)
      end)
    end
  end

  test "statistics" do
    routes = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
        <dataObjects>
          <GeneralFrame>
            <Route id="FR:Route:Route1:" version="any">
            </Route>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    stops = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
        <dataObjects>
          <GeneralFrame>
            <Quay id="FR:Quay:Quay1:" version="any">
            </Quay>
            <Quay id="FR:Quay:Quay2:" version="any">
            </Quay>
            <Quay id="FR:Quay:Quay3:" version="any">
            </Quay>
            <StopPlace id="FR:StopPlace:StopPlace1:" version="any">
            </StopPlace>
            <StopPlace id="FR:StopPlace:StopPlace2:" version="any">
            </StopPlace>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    ZipCreator.with_tmp_zip(
      [{"network.xml", routes}, {"stops.xml", stops}] |> in_sub_directory(),
      fn filepath ->
        assert %{
                 "no_validity_dates" => true,
                 "networks" => [],
                 "modes" => [],
                 "stats" => %{
                   "routes_count" => 1,
                   "quays_count" => 3,
                   "stop_places_count" => 2
                 }
               } ==
                 MetadataExtractor.extract(filepath)
      end
    )
  end

  defp in_sub_directory(filespecs) do
    [{"directory/", ""}] ++
      Enum.map(filespecs, fn {filename, content} -> {Path.join("directory", filename), content} end)
  end
end
