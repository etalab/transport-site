defmodule Unlock.ConfigFetcherTest do
  use ExUnit.Case

  def parse_config(yaml), do: Unlock.Config.Fetcher.convert_yaml_to_config_items(yaml)

  test "parses and converts basic configuration" do
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
