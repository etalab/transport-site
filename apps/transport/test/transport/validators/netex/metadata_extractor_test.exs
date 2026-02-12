defmodule Transport.Validators.NeTEx.MetadataExtractorTest do
  use ExUnit.Case, async: true
  import Transport.TmpFile

  alias Transport.Validators.NeTEx.MetadataExtractor

  test "empty or corrupt file should return empty result silently" do
    for content <- ["", "illegal zip content"] do
      {true, logs} =
        ExUnit.CaptureLog.with_log(fn ->
          with_tmp_file(content, fn filepath ->
            assert %{"no_validity_dates" => true} == MetadataExtractor.extract(filepath)
          end)
        end)

      assert logs =~ "Invalid zip file, missing EOCD record"
    end
  end

  test "empty valid ZIP archive" do
    ZipCreator.with_tmp_zip([], fn filepath ->
      assert %{"no_validity_dates" => true} == MetadataExtractor.extract(filepath)
    end)
  end

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

    ZipCreator.with_tmp_zip([{"resource.xml", calendar_content}], fn filepath ->
      assert %{"start_date" => "2025-07-05", "end_date" => "2025-08-31"} == MetadataExtractor.extract(filepath)
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

    ZipCreator.with_tmp_zip([{"resource.xml", service_calendar_content}], fn filepath ->
      assert %{"start_date" => "2025-11-03", "end_date" => "2025-11-28"} == MetadataExtractor.extract(filepath)
    end)
  end
end
