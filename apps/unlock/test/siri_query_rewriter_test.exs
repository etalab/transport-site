defmodule Unlock.SIRI.QueryRewriterTest do
  use ExUnit.Case
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
  def expected_xml(timestamp, requestor_ref, message_identifier, stop_ref) do
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
  def build_xml(timestamp, requestor_ref, message_id, stop_ref) do
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

    prolog = [version: "1.0"]
    Saxy.encode!(root, prolog)
  end

  def parsed(xml) do
    {:ok, parsed_request} = Saxy.SimpleForm.parse_string(xml, cdata_as_characters: false)
    parsed_request
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

  test "it generates correct XML for testing" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    incoming_requestor_ref = "transport-data-gouv-fr"
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "SomeStopRef"

    assert parsed(build_xml(timestamp, incoming_requestor_ref, message_id, stop_ref)) ==
             filter_newlines_from_model(parsed(expected_xml(timestamp, incoming_requestor_ref, message_id, stop_ref)))
  end

  # adapted from https://github.com/qcam/saxy/blob/master/lib/saxy/simple_form/handler.ex
  defmodule SIRI.QueryTweaker.Handler do
    @moduledoc false

    @behaviour Saxy.Handler

    def handle_event(:start_document, prolog, state), do: Saxy.SimpleForm.Handler.handle_event(:start_document, prolog, state)
    def handle_event(:start_element, data, stack), do: Saxy.SimpleForm.Handler.handle_event(:start_element, data, stack)

    def handle_event(:characters, chars, stack) do
      [{tag_name, attributes, content} | stack] = stack

      # TODO: record the SIRI namespace instead
      unnamespaced_tag = tag_name |> String.split(":") |> List.last

      chars = if (unnamespaced_tag == "RequestorRef") do
        # TODO: attempt to inject this via a compound state
        "NEW-REQUESTOR-REF"
      else
        chars
      end

      current = {tag_name, attributes, [chars | content]}

      {:ok, [current | stack]}
    end

    def handle_event(:cdata, chars, stack), do: Saxy.SimpleForm.Handler.handle_event(:cdata, chars, stack)
    def handle_event(:end_element, tag_name, stack), do: Saxy.SimpleForm.Handler.handle_event(:end_element, tag_name, stack)
    def handle_event(:end_document, some_param, stack), do: Saxy.SimpleForm.Handler.handle_event(:end_document, some_param, stack)
  end

  test "dynamic requestor_ref modification" do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    incoming_requestor_ref = "transport-data-gouv-fr"
    message_id = "Test::Message::#{Ecto.UUID.generate()}"
    stop_ref = "SomeStopRef"

    xml = build_xml(timestamp, incoming_requestor_ref, message_id, stop_ref)
    {:ok, parsed} = Saxy.parse_string(xml, SIRI.QueryTweaker.Handler, [])
    expected_output = expected_xml(timestamp, "NEW-REQUESTOR-REF", message_id, stop_ref)

    assert parsed |> filter_newlines_from_model == expected_output |> parsed() |> filter_newlines_from_model
  end
end
