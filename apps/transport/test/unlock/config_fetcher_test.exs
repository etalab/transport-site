defmodule Unlock.ConfigFetcherTest do
  use ExUnit.Case

  def parse_config(yaml), do: Unlock.Config.Fetcher.convert_yaml_to_config_items(yaml)

  [
    %{config_type: "gtfs-rt"},
    %{config_type: "generic-http"}
  ]
  |> Enum.each(fn %{config_type: config_type} ->
    describe "for #{config_type} items" do
      # default value must be respected
      if config_type == "gtfs-rt" do
        test "type defaults to gtfs-rt" do
          yaml_config = """
          ---
          feeds:
            - identifier: "httpbin-get"
              target_url: "https://httpbin.org/get"
              # no type provided
              ttl: 10
          """

          assert parse_config(yaml_config) == [
                   %Unlock.Config.Item.Generic.HTTP{
                     identifier: "httpbin-get",
                     target_url: "https://httpbin.org/get",
                     # gtfs-rt must be stored
                     subtype: "gtfs-rt",
                     ttl: 10
                   }
                 ]
        end
      end

      test "parses and converts configuration" do
        yaml_config = """
        ---
        feeds:
          - identifier: "httpbin-get"
            target_url: "https://httpbin.org/get"
            type: #{unquote(config_type)}
            ttl: 10
        """

        assert parse_config(yaml_config) == [
                 %Unlock.Config.Item.Generic.HTTP{
                   identifier: "httpbin-get",
                   target_url: "https://httpbin.org/get",
                   # default value
                   subtype: unquote(config_type),
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
            type: #{unquote(config_type)}
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
            type: #{unquote(config_type)}
            request_headers:
              - ["Authorization", "Bearer some-value"]
        """

        [item] = parse_config(yaml_config)

        assert item.request_headers == [{"Authorization", "Bearer some-value"}]
      end
    end
  end)

  describe "for SIRI items" do
    test "it parses basic information" do
      yaml_config = """
      ---
      feeds:
        - identifier: "httpbin-get"
          type: "siri"
          target_url: "https://httpbin.org/get"
          requestor_ref: the-ref
      """

      assert parse_config(yaml_config) == [
               %Unlock.Config.Item.SIRI{
                 identifier: "httpbin-get",
                 target_url: "https://httpbin.org/get",
                 requestor_ref: "the-ref"
               }
             ]
    end
  end

  describe "for aggregated items" do
    test "it parses basic information" do
      yaml_config = """
      ---
      feeds:
        - identifier: "consolidation"
          type: "aggregate"
          feeds:
            - identifier: abdcd
              slug: foo
              target_url: http://localhost:1234
              ttl: 100
            - identifier: efghi
              slug: bar
              target_url: https://localhost:1235
      """

      assert parse_config(yaml_config) == [
               %Unlock.Config.Item.Aggregate{
                 identifier: "consolidation",
                 ttl: 10,
                 feeds: [
                   %Unlock.Config.Item.Generic.HTTP{
                     identifier: "abdcd",
                     slug: "foo",
                     target_url: "http://localhost:1234",
                     ttl: 100,
                     subtype: "generic-http"
                   },
                   %Unlock.Config.Item.Generic.HTTP{
                     identifier: "efghi",
                     slug: "bar",
                     target_url: "https://localhost:1235",
                     ttl: 10,
                     subtype: "generic-http"
                   }
                 ]
               }
             ]
    end
  end
end
