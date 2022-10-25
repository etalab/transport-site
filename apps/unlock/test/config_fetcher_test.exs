defmodule Unlock.ConfigFetcherTest do
  use ExUnit.Case, async: true

  def parse_config(yaml), do: Unlock.Config.Fetcher.convert_yaml_to_config_items(yaml)

  describe "for GTFS-RT items" do
    test "parses and converts configuration" do
      yaml_config = """
      ---
      feeds:
        - identifier: "httpbin-get"
          target_url: "https://httpbin.org/get"
          ttl: 10
      """

      assert parse_config(yaml_config) == [
               %Unlock.Config.Item.GTFS.RT{
                 identifier: "httpbin-get",
                 target_url: "https://httpbin.org/get",
                 ttl: 10
               }
             ]
    end

    test "defaults to TTL 0 if TTL is unspecified" do
      yaml_config = """
      ---
      feeds:
        - identifier: "httpbin-get"
          target_url: "https://httpbin.org/get"
      """

      [item] = parse_config(yaml_config)

      assert item.ttl == 0
    end

    # This was the cleanest/most robust way I could find to express this in YAML
    test "supports requests headers as array of 2-element arrays, mapped into tuples" do
      yaml_config = """
      ---
      feeds:
        - identifier: "httpbin-header-auth-ok"
          target_url: "https://httpbin.org/bearer"
          request_headers:
            - ["Authorization", "Bearer some-value"]
      """

      [item] = parse_config(yaml_config)

      assert item.request_headers == [{"Authorization", "Bearer some-value"}]
    end
  end

  describe "for SIRI items" do
    test "it parses basic information" do
      yaml_config = """
      ---
      feeds:
        - identifier: "httpbin-get"
          type: "siri"
          target_url: "https://httpbin.org/get"
          requestor_ref: the-ref
          allowed_queries:
            - CheckStatus
            - GetStopMonitoring
      """

      assert parse_config(yaml_config) == [
               %Unlock.Config.Item.SIRI{
                 identifier: "httpbin-get",
                 target_url: "https://httpbin.org/get",
                 requestor_ref: "the-ref",
                 allowed_queries: ["CheckStatus", "GetStopMonitoring"]
               }
             ]
    end
  end

  test "request_is_allowed" do
    item = %Unlock.Config.Item.SIRI{
      identifier: "httpbin-get",
      target_url: "https://httpbin.org/get",
      requestor_ref: "the-ref",
      allowed_queries: []
    }

    parsed_xml =
      """
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
      |> Unlock.SIRI.parse_incoming()

    assert Unlock.Config.Item.SIRI.request_is_allowed?(item, parsed_xml)
    assert Unlock.Config.Item.SIRI.request_is_allowed?(%{item | allowed_queries: ["CheckStatus"]}, parsed_xml)

    assert Unlock.Config.Item.SIRI.request_is_allowed?(
             %{item | allowed_queries: ["CheckStatus", "LinesDiscovery"]},
             parsed_xml
           )

    refute Unlock.Config.Item.SIRI.request_is_allowed?(%{item | allowed_queries: ["LinesDiscovery"]}, parsed_xml)
  end
end
