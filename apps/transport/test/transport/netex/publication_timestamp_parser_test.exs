defmodule Transport.NeTEx.PublicationTimestampParserTest do
  use ExUnit.Case, async: true

  alias Transport.NeTEx.PublicationTimestampParser

  describe "parsing PublicationTimestamp" do
    test "extracts valid ISO 8601 date with Z suffix" do
      xml = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex">
          <PublicationTimestamp>2025-07-29T09:34:55Z</PublicationTimestamp>
        </PublicationDelivery>
      """

      {:ok, state} = Saxy.parse_string(xml, PublicationTimestampParser, PublicationTimestampParser.initial_state())
      assert %Date{year: 2025, month: 7, day: 29} = PublicationTimestampParser.unwrap_result(state)
    end

    test "extracts valid ISO 8601 date without Z suffix" do
      xml = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex">
          <PublicationTimestamp>2025-07-29T09:34:55</PublicationTimestamp>
        </PublicationDelivery>
      """

      {:ok, state} = Saxy.parse_string(xml, PublicationTimestampParser, PublicationTimestampParser.initial_state())
      assert %Date{year: 2025, month: 7, day: 29} = PublicationTimestampParser.unwrap_result(state)
    end

    test "extracts valid date with offset" do
      xml = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex">
          <PublicationTimestamp>2025-07-29T11:34:55+02:00</PublicationTimestamp>
        </PublicationDelivery>
      """

      {:ok, state} = Saxy.parse_string(xml, PublicationTimestampParser, PublicationTimestampParser.initial_state())
      assert %Date{year: 2025, month: 7, day: 29} = PublicationTimestampParser.unwrap_result(state)
    end

    test "returns nil when no PublicationTimestamp element" do
      xml = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex">
          <ParticipantRef>DIGO</ParticipantRef>
        </PublicationDelivery>
      """

      {:ok, state} = Saxy.parse_string(xml, PublicationTimestampParser, PublicationTimestampParser.initial_state())
      assert nil == PublicationTimestampParser.unwrap_result(state)
    end

    test "returns nil when PublicationTimestamp contains invalid date" do
      xml = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex">
          <PublicationTimestamp>not-a-date</PublicationTimestamp>
        </PublicationDelivery>
      """

      {:ok, state} = Saxy.parse_string(xml, PublicationTimestampParser, PublicationTimestampParser.initial_state())
      assert nil == PublicationTimestampParser.unwrap_result(state)
    end

    test "captures first timestamp when multiple exist" do
      xml = """
        <PublicationDelivery xmlns="http://www.netex.org.uk/netex">
          <PublicationTimestamp>2025-01-15T00:00:00Z</PublicationTimestamp>
          <dataObjects>
            <GeneralFrame id="frame1">
              <PublicationTimestamp>2025-06-01T00:00:00Z</PublicationTimestamp>
            </GeneralFrame>
          </dataObjects>
        </PublicationDelivery>
      """

      {:ok, state} = Saxy.parse_string(xml, PublicationTimestampParser, PublicationTimestampParser.initial_state())
      assert %Date{year: 2025, month: 1, day: 15} = PublicationTimestampParser.unwrap_result(state)
    end
  end
end
