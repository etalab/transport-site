# Ref: http://www.normes-donnees-tc.org/wp-content/uploads/2021/09/BNTRA-CN03-GT7_NF-Profil-SIRI-FR_v1.2_20210308.pdf
defmodule Transport.SIRI do
  @moduledoc """
  A module to build SIRI queries.
  """

  import Saxy.XML

  @top_level_namespaces [
    {"xmlns:S", "http://schemas.xmlsoap.org/soap/envelope/"},
    {"xmlns:SOAP-ENV", "http://schemas.xmlsoap.org/soap/envelope/"}
  ]

  @request_namespaces [
    {"xmlns:sw", "http://wsdl.siri.org.uk"},
    {"xmlns:siri", "http://www.siri.org.uk/siri"}
  ]

  def prolog do
    ~S(<?xml version="1.0" encoding="UTF-8"?>)
  end

  def check_status(timestamp, requestor_ref, message_identifier) do
    element("S:Envelope", @top_level_namespaces, [
      element("S:Body", [], [
        element("sw:CheckStatus", @request_namespaces, [
          element("Request", [], [
            element("siri:RequestTimestamp", [], timestamp),
            element("siri:RequestorRef", [], requestor_ref),
            element("siri:MessageIdentifier", [], message_identifier)
          ])
        ])
      ])
    ])
    |> Saxy.encode!()
  end

  def lines_discovery(timestamp, requestor_ref, message_identifier) do
    """
    #{prolog()}
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
  end

  def stop_points_discovery(timestamp, requestor_ref, message_identifier) do
    """
    #{prolog()}
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
  end

  def build_line_refs(line_refs) do
    # NOTE: we'll switch to proper well-escaped XML building later, this is research code
    line_refs = line_refs |> Enum.map_join("\n", &"<siri:LineRef>#{&1}</siri:LineRef>")

    """
    <siri:Lines>
      #{line_refs}
    </siri:Lines>
    """
  end

  def get_estimated_timetable(timestamp, requestor_ref, message_identifier, line_refs) do
    """
    #{prolog()}
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
                #{build_line_refs(line_refs)}
            </Request>
        </sw:GetEstimatedTimetable>
      </S:Body>
    </S:Envelope>
    """
  end

  def get_stop_monitoring(timestamp, requestor_ref, message_identifier, stop_ref) do
    """
    #{prolog()}
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
        <sw:GetStopMonitoring xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
            <ServiceRequestInfo>
                <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
                <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
                <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
            </ServiceRequestInfo>
            <Request version="2.0:FR-IDF-2.4">
                <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
                <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
                <siri:MonitoringRef>#{stop_ref}</siri:MonitoringRef>
                <siri:StopVisitTypes>all</siri:StopVisitTypes>
            </Request>
        </sw:GetStopMonitoring>
    </S:Body>
    </S:Envelope>
    """
  end

  def get_general_message(timestamp, requestor_ref, message_identifier) do
    """
    #{prolog()}
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
     	<sw:GetGeneralMessage xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri" xmlns:sws="http://wsdl.siri.org.uk/siri">
        	<ServiceRequestInfo>
    		      <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
    		      <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
            	<siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
         </ServiceRequestInfo>
         <Request version="2.0:FR-IDF-2.4">
                <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
                <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
      			</Request>
    		</sw:GetGeneralMessage>
    </S:Body>
    </S:Envelope>
    """
  end
end
