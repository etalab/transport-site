defmodule Transport.NeTEx.ArchiveParserTest do
  use ExUnit.Case, async: true

  # not fully correct XML, but close enough for what we want to test
  def some_netex_content do
    """
        <GeneralFrame>
          <members>
            <StopPlace id="FR:HELLO:POYARTIN:001">
            <Name>Poyartin</Name>
            <Centroid>
              <Location>
                <Latitude>43.6690</Latitude>
                <Longitude>-0.9190</Longitude>
              </Location>
            </Centroid>
          </StopPlace>
        </members>
      </GeneralFrame>
    """
  end

  test "traverse the archive and return relevant content" do
    tmp_file = create_tmp_netex([{"arrets.xml", some_netex_content()}])

    # given a zip netex archive containing 1 file, I want the output I expected
    [{"arrets.xml", data}] = Transport.NeTEx.read_all_stop_places(tmp_file)

    assert data ==
             {:ok,
              [
                %{id: "FR:HELLO:POYARTIN:001", latitude: 43.669, longitude: -0.919, name: "Poyartin"}
              ]}

    # given a zip netex archive containing 1 file, I want the output I expected
    [{"arrets.xml", data}] = Transport.NeTEx.read_all_stop_places!(tmp_file)

    assert data == [
             %{id: "FR:HELLO:POYARTIN:001", latitude: 43.669, longitude: -0.919, name: "Poyartin"}
           ]
  end

  test "extract validity dates from service calendars" do
    service_calendar_content = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" xmlns:siri="http://www.siri.org.uk/siri" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" xsi:schemaLocation="http://www.netex.org.uk/netex ../../../xsd/NeTEx_publication.xsd">
        <dataObjects>
          <ServiceCalendarFrame version="any">
            <Name>Calender Example for Netex   GD</Name>
            <ServiceCalendar version="any" id="ust:FullYear2026">
              <FromDate>2026-01-01</FromDate>
              <ToDate>2026-12-31</ToDate>
            </ServiceCalendar>
          </ServiceCalendarFrame>
          <ServiceCalendarFrame version="any" id="LIO:ServiceCalendarFrame:0:LOC">
            <TypeOfFrameRef ref="FR:TypeOfFrame:NETEX_CALENDRIER:"/>
            <dayTypes>
              <DayType version="any" id="LIO:DayType:6e68183c42604e2d0f67">
                <ValidBetween>
                  <FromDate>2025-11-03T00:00:00</FromDate>
                  <ToDate>2025-11-15T00:00:00</ToDate>
                </ValidBetween>
                <Name>2025-07-25 → 11-15 (16 lun, 15 mar, 16 mer, 16 jeu, 16 ven, 16 sam)</Name>
              </DayType>
              <DayType version="any" id="LIO:DayType:5d21656b7c1e4d2b0557">
                <ValidBetween>
                  <FromDate>2025-11-03T00:00:00</FromDate>
                  <ToDate>2025-11-28T00:00:00</ToDate>
                </ValidBetween>
                <Name>2025-07-25 → 11-28 (18 lun, 17 mar, 18 mer, 18 jeu, 18 ven)</Name>
              </DayType>
            </dayTypes>
          </ServiceCalendarFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    data = extract(&Transport.NeTEx.read_all_service_calendars!/1, service_calendar_content)

    assert [
             %{
               id: "ust:FullYear2026",
               name: "Calender Example for Netex   GD",
               start_date: Date.from_iso8601!("2026-01-01"),
               end_date: Date.from_iso8601!("2026-12-31")
             },
             %{
               id: "LIO:DayType:6e68183c42604e2d0f67",
               name: "2025-07-25 → 11-15 (16 lun, 15 mar, 16 mer, 16 jeu, 16 ven, 16 sam)",
               start_date: Date.from_iso8601!("2025-11-03"),
               end_date: Date.from_iso8601!("2025-11-15")
             },
             %{
               id: "LIO:DayType:5d21656b7c1e4d2b0557",
               name: "2025-07-25 → 11-28 (18 lun, 17 mar, 18 mer, 18 jeu, 18 ven)",
               start_date: Date.from_iso8601!("2025-11-03"),
               end_date: Date.from_iso8601!("2025-11-28")
             }
           ] == data

    empty_service_calendar_content = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" xmlns:siri="http://www.siri.org.uk/siri" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="1.0" xsi:schemaLocation="http://www.netex.org.uk/netex ../../../xsd/NeTEx_publication.xsd">
        <dataObjects>
          <ServiceCalendarFrame id="FR:1:ServiceCalendarFrame:j19" version="any">
            <dayTypes>
              <DayType id="FR:DayType:1:" version="any"/>
              <DayType id="FR:DayType:2:" version="any"/>
              <DayType id="FR:DayType:3:" version="any"/>
            </dayTypes>
          </ServiceCalendarFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    data = extract(&Transport.NeTEx.read_all_service_calendars!/1, empty_service_calendar_content)

    assert [] == data
  end

  test "extract validity dates from calendar" do
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
            <TypeOfFrameRef ref="FR:TypeOfFrame:NETEX_CALENDRIER:">version="1.1:FR-NETEX_CALENDRIER-2.2"</TypeOfFrameRef>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    data = extract(&Transport.NeTEx.read_all_calendars!/1, calendar_content)

    assert [
             %{
               id: "DIGO:GeneralFrame:NETEX_CALENDRIER-20250729093455Z:LOC",
               start_date: Date.from_iso8601!("2025-07-05"),
               end_date: Date.from_iso8601!("2025-08-31")
             }
           ] == data

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

    data = extract(&Transport.NeTEx.read_all_calendars!/1, calendar_content)

    assert [
             %{
               id: "DIGO:GeneralFrame:NETEX_CALENDRIER-20250729093455Z:LOC",
               start_date: Date.from_iso8601!("2025-07-05"),
               end_date: Date.from_iso8601!("2025-08-31")
             }
           ] == data

    idfm_calendar_content = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
        <PublicationTimestamp>2026-02-02T15:45:04Z</PublicationTimestamp>
        <ParticipantRef>FR1_OFFRE</ParticipantRef>
        <dataObjects>
          <GeneralFrame id="FR1:GeneralFrame:NETEX_CALENDRIER-20260202T154504Z:LOC" version="1.8" dataSourceRef="FR1-OFFRE_AUTO">
            <ValidBetween>
              <FromDate>2026-02-02T00:00:00+00:00</FromDate>
              <ToDate>2026-03-03T00:00:00+00:00</ToDate>
            </ValidBetween>
            <TypeOfFrameRef ref="FR1:TypeOfFrame:NETEX_CALENDRIER:"/>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    data = extract(&Transport.NeTEx.read_all_calendars!/1, idfm_calendar_content)

    assert [
             %{
               id: "FR1:GeneralFrame:NETEX_CALENDRIER-20260202T154504Z:LOC",
               start_date: Date.from_iso8601!("2026-02-02"),
               end_date: Date.from_iso8601!("2026-03-03")
             }
           ] == data
  end

  test "extract validity dates from opertating periods" do
    operating_periods = """
      <GeneralFrame id="FR:GeneralFrame:NETEX_CALENDRIER:LOC" version="1.09:FR-NETEX-2.1-1.0">
        <TypeOfFrameRef ref="FR:TypeOfFrame:NETEX_CALENDRIER:"/>
        <members>
          <UicOperatingPeriod id="chouette:OperatingPeriod:7b424a03-552c-4833-9a91-e6b2e58c2c26-54:LOC" version="any">
            <FromDate>2025-12-22T00:00:00</FromDate>
            <ToDate>2026-12-22T00:00:00</ToDate>
          </UicOperatingPeriod>
        </members>
      </GeneralFrame>
    """

    data = extract(&Transport.NeTEx.read_all_calendars!/1, operating_periods)

    assert [
             %{
               id: "chouette:OperatingPeriod:7b424a03-552c-4833-9a91-e6b2e58c2c26-54:LOC",
               start_date: Date.from_iso8601!("2025-12-22"),
               end_date: Date.from_iso8601!("2026-12-22")
             }
           ] == data
  end

  test "extract TypeOfFrames" do
    general_frame = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
        <PublicationTimestamp>2026-02-02T15:45:04Z</PublicationTimestamp>
        <ParticipantRef>FR1_OFFRE</ParticipantRef>
        <dataObjects>
          <GeneralFrame id="FR:GeneralFrame:NETEX_CALENDRIER:LOC" version="1.09:FR-NETEX-2.1-1.0">
            <TypeOfFrameRef ref="FR:TypeOfFrame:NETEX_CALENDRIER:"/>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    assert ["NETEX_CALENDRIER"] == extract(&Transport.NeTEx.read_all_types_of_frames!/1, general_frame)

    composite_frames = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
        <PublicationTimestamp>2026-02-02T15:45:04Z</PublicationTimestamp>
        <ParticipantRef>FR1_OFFRE</ParticipantRef>
        <dataObjects>
          <CompositeFrame id="FR1:CompositeFrame:NETEX_OFFRE_LIGNE-20260202T154504Z:LOC" version="1.8" dataSourceRef="FR1-OFFRE_AUTO">
            <Name>6201</Name>
            <TypeOfFrameRef ref="FR1:TypeOfFrame:NETEX_N_LIGNE:"/>
            <frames>
              <GeneralFrame id="FR1:GeneralFrame:NETEX_STRUCTURE-20260202T154504Z:LOC" version="1.8" dataSourceRef="FR1-OFFRE_AUTO">
                <TypeOfFrameRef ref="FR1:TypeOfFrame:NETEX_LIGNE:"/>
              </GeneralFrame>
            </frames>
          </CompositeFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    assert ["NETEX_N_LIGNE", "NETEX_LIGNE"] == extract(&Transport.NeTEx.read_all_types_of_frames!/1, composite_frames)

    non_standard_types = """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" version="1.04:FR1-NETEX-1.6-1.8">
        <PublicationTimestamp>2026-02-02T15:45:04Z</PublicationTimestamp>
        <ParticipantRef>FR1_OFFRE</ParticipantRef>
        <dataObjects>
          <CompositeFrame id="FR1:CompositeFrame:NETEX_OFFRE_LIGNE-20260202T154504Z:LOC" version="1.8" dataSourceRef="FR1-OFFRE_AUTO">
            <Name>6201</Name>
            <TypeOfFrameRef ref="FR1:TypeOfFrame:NETEX_OFFRE_LIGNE:"/>
            <frames>
              <GeneralFrame id="FR1:GeneralFrame:NETEX_STRUCTURE-20260202T154504Z:LOC" version="1.8" dataSourceRef="FR1-OFFRE_AUTO">
                <TypeOfFrameRef ref="FR1:TypeOfFrame:NETEX_STRUCTURE:"/>
              </GeneralFrame>
            </frames>
          </CompositeFrame>
        </dataObjects>
      </PublicationDelivery>
    """

    types = extract(&Transport.NeTEx.read_all_types_of_frames!/1, non_standard_types)

    assert [] == types
  end

  defp extract(extractor, xml) do
    tmp_file = create_tmp_netex([{"file.xml", xml}])

    [{"file.xml", types}] = extractor.(tmp_file)

    types
  end

  defp create_tmp_netex(files) do
    tmp_file = System.tmp_dir!() |> Path.join("temp-netex-#{Ecto.UUID.generate()}.zip")
    ZipCreator.create!(tmp_file, files)
    tmp_file
  end
end
