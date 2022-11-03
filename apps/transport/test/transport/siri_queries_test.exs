defmodule Transport.SIRITest do
  use ExUnit.Case

  # see https://github.com/qcam/saxy/issues/103
  defmodule XMLNewlinesRemover do
    def filter_newlines_from_model({element, tags, children}) do
      {
        element,
        tags,
        children
        |> Enum.map(&filter_newlines_from_model/1)
        |> Enum.reject(&is_nil/1)
      }
    end

    def filter_newlines_from_model(content) when is_binary(content) do
      if content |> String.trim() == "", do: nil, else: content
    end
  end

  @doc """
  To make it easier to compare XML strings during test, we parse them as
  Elixir structures, and removing the non-significant newlines.
  """
  def parse_xml(payload) do
    payload
    |> Unlock.SIRI.parse_incoming()
    |> XMLNewlinesRemover.filter_newlines_from_model()
  end

  test "CheckStatus" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    request = Transport.SIRI.check_status(timestamp, requestor_ref, message_identifier)

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <sw:CheckStatus xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
          <Request>
            <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
            <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
            <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
          </Request>
        </sw:CheckStatus>
      </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end

  test "LinesDiscovery" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    request = Transport.SIRI.lines_discovery(timestamp, requestor_ref, message_identifier)

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <sw:LinesDiscovery xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
          <Request>
            <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
            <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
            <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
          </Request>
        </sw:LinesDiscovery>
      </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end

  test "StopPointsDiscovery" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    request = Transport.SIRI.stop_points_discovery(timestamp, requestor_ref, message_identifier)

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <sw:StopPointsDiscovery xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
          <Request>
            <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
            <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
            <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
          </Request>
        </sw:StopPointsDiscovery>
      </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end

  test "GetEstimatedTimetable (with line references)" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    line_001 = "LINE:001"
    line_002 = "LINE:002"
    request = Transport.SIRI.get_estimated_timetable(timestamp, requestor_ref, message_identifier, [line_001, line_002])

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <sw:GetEstimatedTimetable xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
            <ServiceRequestInfo>
              <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
              <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
              <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
            </ServiceRequestInfo>
            <Request>
              <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
              <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
              <siri:Lines>
                <siri:LineRef>#{line_001}</siri:LineRef>
                <siri:LineRef>#{line_002}</siri:LineRef>
              </siri:Lines>
            </Request>
        </sw:GetEstimatedTimetable>
      </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end

  # NOTE: there are apparently differently ways to create this ("ALL" vs "nothing")
  # and different servers exhibit different behaviours (to be verified).
  test "GetEstimatedTimetable (without line references)" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    request = Transport.SIRI.get_estimated_timetable(timestamp, requestor_ref, message_identifier, [])

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <sw:GetEstimatedTimetable xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
            <ServiceRequestInfo>
              <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
              <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
              <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
            </ServiceRequestInfo>
            <Request>
              <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
              <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
            </Request>
        </sw:GetEstimatedTimetable>
      </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end

  test "GetGeneralMessage" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    request = Transport.SIRI.get_general_message(timestamp, requestor_ref, message_identifier)

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
     	<sw:GetGeneralMessage xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri" xmlns:sws="http://wsdl.siri.org.uk/siri">
        <ServiceRequestInfo>
          <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
          <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
          <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
        </ServiceRequestInfo>
        <Request>
          <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
          <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
        </Request>
      </sw:GetGeneralMessage>
    </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end

  test "GetStopMonitoring" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    requestor_ref = "the-ref"
    message_identifier = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "STOP:001"
    request = Transport.SIRI.get_stop_monitoring(timestamp, requestor_ref, message_identifier, stop_ref)

    expected_response = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
      <sw:GetStopMonitoring xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
        <ServiceRequestInfo>
          <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
          <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
          <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
        </ServiceRequestInfo>
        <Request>
          <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
          <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
          <siri:MonitoringRef>#{stop_ref}</siri:MonitoringRef>
          <siri:StopVisitTypes>all</siri:StopVisitTypes>
        </Request>
      </sw:GetStopMonitoring>
    </S:Body>
    </S:Envelope>
    """

    assert parse_xml(request) == parse_xml(expected_response)
  end
end
