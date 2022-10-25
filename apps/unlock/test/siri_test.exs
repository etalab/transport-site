defmodule Unlock.SIRITests do
  use ExUnit.Case, async: true
  import SIRIQueries

  doctest Unlock.SIRI
  doctest Unlock.SIRI.RequestorRefReplacer

  test "requestor ref can be changed on the fly" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    incoming_requestor_ref = "transport-data-gouv-fr"
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "SomeStopRef"

    # build some XML to simulate the input
    input_xml = siri_query_from_builder(timestamp, incoming_requestor_ref, message_id, stop_ref)

    # fake the parsing occurring in the controller
    parsed = Unlock.SIRI.parse_incoming(input_xml)

    {xml, seen_requestor_refs} = Unlock.SIRI.RequestorRefReplacer.replace_requestor_ref(parsed, "new-requestor-ref")

    # the returned XML must have its requestor ref replaced
    assert xml ==
             timestamp
             |> siri_query_from_builder("new-requestor-ref", message_id, stop_ref)
             |> Unlock.SIRI.parse_incoming()

    # and the input requestor ref seen in the document must be returned
    assert seen_requestor_refs == [incoming_requestor_ref]
  end

  test "ServicesFinder parses services" do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
        <sw:CheckStatus xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
            <Request>
                <siri:RequestTimestamp>#{DateTime.utc_now() |> DateTime.to_iso8601()}</siri:RequestTimestamp>
                <siri:RequestorRef>secret</siri:RequestorRef>
                <siri:MessageIdentifier>Test:Message::9d5f99e2-5e6d-4c7b-befc-381a3c592ede</siri:MessageIdentifier>
            </Request>
            <RequestExtension/>
        </sw:CheckStatus>
    </S:Body>
    </S:Envelope>
    """

    assert ["CheckStatus"] == xml |> Unlock.SIRI.parse_incoming() |> Unlock.SIRI.ServicesFinder.parse()

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
        <sw:CheckStatus xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
          <Request>
            <siri:RequestTimestamp>2022-10-25T08:34:59.247129Z</siri:RequestTimestamp>
            <siri:RequestorRef>transport-data-gouv-fr</siri:RequestorRef>
            <siri:MessageIdentifier>Test::Message::64026718-3b56-4b93-a37f-7e542097a3e3</siri:MessageIdentifier>
          </Request>
        </sw:CheckStatus>
        <sw:LinesDiscovery xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
          <Request>
            <siri:RequestTimestamp>2022-10-25T08:34:59.247129Z</siri:RequestTimestamp>
            <siri:RequestorRef>transport-data-gouv-fr</siri:RequestorRef>
            <siri:MessageIdentifier>Test::Message::64026718-3b56-4b93-a37f-7e542097a3e3</siri:MessageIdentifier>
          </Request>
        </sw:LinesDiscovery>
      </S:Body>
    </S:Envelope>
    """

    assert ["CheckStatus", "LinesDiscovery"] ==
             xml |> Unlock.SIRI.parse_incoming() |> Unlock.SIRI.ServicesFinder.parse()

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
      <S:Body>
      </S:Body>
    </S:Envelope>
    """

    assert [] == xml |> Unlock.SIRI.parse_incoming() |> Unlock.SIRI.ServicesFinder.parse()
  end
end
