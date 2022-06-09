defmodule SIRIQueries do
  import Saxy.XML

  @top_level_namespaces [
    {"xmlns:S", "http://schemas.xmlsoap.org/soap/envelope/"},
    {"xmlns:SOAP-ENV", "http://schemas.xmlsoap.org/soap/envelope/"}
  ]

  @request_namespaces [
    {"xmlns:sw", "http://wsdl.siri.org.uk"},
    {"xmlns:siri", "http://www.siri.org.uk/siri"}
  ]

  # original pattern from the experimental SIRI scripts, used as a basis of comparison
  # to build something more API-esque, which will be useful for more flexible testing
  def siri_query_from_template(timestamp, requestor_ref, message_identifier, stop_ref) do
    """
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
  end

  # a more flexible way to build SIRI queries
  def siri_query_from_builder(timestamp, requestor_ref, message_id, stop_ref) do
    root =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:GetStopMonitoring", @request_namespaces, [
            element("ServiceRequestInfo", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_id)
            ]),
            element("Request", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:MessageIdentifier", [], message_id),
              element("siri:MonitoringRef", [], stop_ref),
              element("siri:StopVisitTypes", [], "all")
            ])
          ])
        ])
      ])

    Saxy.encode!(root, version: "1.0")
  end

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
