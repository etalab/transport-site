# Links:
# - http://www.normes-donnees-tc.org/wp-content/uploads/2021/09/BNTRA-CN03-GT7_NF-Profil-SIRI-FR_v1.2_20210308.pdf
# - https://github.com/SIRI-CEN/SIRI
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

  def request_extension, do: empty_element("RequestExtension", [])

  def check_status(timestamp, requestor_ref, message_identifier) do
    doc =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:CheckStatus", @request_namespaces, [
            element("Request", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_identifier)
            ]),
            request_extension()
          ])
        ])
      ])

    Saxy.encode!(doc)
  end

  def lines_discovery(timestamp, requestor_ref, message_identifier) do
    doc =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:LinesDiscovery", @request_namespaces, [
            element("Request", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_identifier)
            ]),
            request_extension()
          ])
        ])
      ])

    Saxy.encode!(doc)
  end

  def stop_points_discovery(timestamp, requestor_ref, message_identifier) do
    doc =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:StopPointsDiscovery", @request_namespaces, [
            element("Request", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_identifier)
            ]),
            request_extension()
          ])
        ])
      ])

    Saxy.encode!(doc)
  end

  def line_refs_element([] = _line_refs), do: nil

  def line_refs_element(line_refs) do
    element("siri:Lines", [], Enum.map(line_refs, fn line_ref ->
      element("siri:LineDirection", [], [
        element("siri:LineRef", [], line_ref)
      ])
    end))
  end

  def append_if_not_nil(list, nil), do: list
  def append_if_not_nil(list, item), do: list ++ [item]

  def get_estimated_timetable(timestamp, requestor_ref, message_identifier, line_refs) do
    doc =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:GetEstimatedTimetable", @request_namespaces, [
            element("ServiceRequestInfo", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_identifier)
            ]),
            element(
              "Request",
              [],
              [
                element("siri:RequestTimestamp", [], timestamp),
                element("siri:MessageIdentifier", [], message_identifier)
              ]
              |> append_if_not_nil(line_refs_element(line_refs))
            ),
            request_extension()
          ])
        ])
      ])

    Saxy.encode!(doc)
  end

  def get_stop_monitoring(timestamp, requestor_ref, message_identifier, stop_ref) do
    doc =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:GetStopMonitoring", @request_namespaces, [
            element("ServiceRequestInfo", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_identifier)
            ]),
            element(
              "Request",
              [],
              [
                element("siri:RequestTimestamp", [], timestamp),
                element("siri:MessageIdentifier", [], message_identifier),
                element("siri:MonitoringRef", [], stop_ref),
                element("siri:StopVisitTypes", [], "all")
              ]
            ),
            request_extension()
          ])
        ])
      ])

    Saxy.encode!(doc)
  end

  def get_general_message(timestamp, requestor_ref, message_identifier) do
    doc =
      element("S:Envelope", @top_level_namespaces, [
        element("S:Body", [], [
          element("sw:GetGeneralMessage", @request_namespaces, [
            element("ServiceRequestInfo", [], [
              element("siri:RequestTimestamp", [], timestamp),
              element("siri:RequestorRef", [], requestor_ref),
              element("siri:MessageIdentifier", [], message_identifier)
            ]),
            element(
              "Request",
              [],
              [
                element("siri:RequestTimestamp", [], timestamp),
                element("siri:MessageIdentifier", [], message_identifier)
              ]
            ),
            request_extension()
          ])
        ])
      ])

    Saxy.encode!(doc)
  end
end
