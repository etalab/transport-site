defmodule Transport.Shared.GBFSMetadataTest do
  use ExUnit.Case, async: true

  import Mox
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  import Transport.Shared.GBFSMetadata
  import ExUnit.CaptureLog
  doctest Transport.Shared.GBFSMetadata

  @gbfs_url "https://example.com/gbfs.json"

  setup :verify_on_exit!

  describe "Compute GBFS metadata for a feed" do
    test "for a stations feed with a single version" do
      setup_feeds([:gbfs, :system_information, :station_information])
      setup_validation_result()

      assert %{
               languages: ["fr"],
               system_details: %{name: "velhop", timezone: "Europe/Paris"},
               ttl: 3600,
               types: ["stations"],
               versions: ["1.1"],
               feeds: ["system_information", "station_information", "station_status"],
               validation: %GBFSValidationSummary{
                 errors_count: 0,
                 has_errors: false,
                 version_detected: "1.1",
                 version_validated: "1.1",
                 validator_version: "31c5325",
                 validator: :validator_module
               },
               cors_header_value: "*",
               feed_timestamp_delay: _,
               vehicle_types: ["bicycle"]
             } = compute_feed_metadata(@gbfs_url, "http://example.com")
    end

    test "for a stations + free floating feed with a multiple versions" do
      setup_feeds([:gbfs_with_versions, :gbfs_versions, :system_information, :vehicle_types, :free_bike_status])

      setup_validation_result(
        {:ok, summary} =
          {:ok,
           %GBFSValidationSummary{
             errors_count: 0,
             has_errors: false,
             version_detected: "2.2",
             version_validated: "2.2",
             validator_version: "31c5325",
             validator: :validator_module
           }}
      )

      assert %{
               languages: ["fr"],
               system_details: %{name: "velhop", timezone: "Europe/Paris"},
               ttl: 60,
               types: ["free_floating", "stations"],
               validation: ^summary,
               versions: ["2.2", "2.1"],
               feeds: [
                 "system_information",
                 "free_bike_status",
                 "vehicle_types",
                 "system_pricing_plans",
                 "station_information",
                 "station_status",
                 "geofencing_zones",
                 "gbfs_versions"
               ],
               cors_header_value: "*",
               feed_timestamp_delay: feed_timestamp_delay,
               vehicle_types: ["bicycle", "scooter"]
             } = compute_feed_metadata(@gbfs_url, "http://example.com")

      assert feed_timestamp_delay > 0
    end

    test "for feed with a 500 error on the root URL" do
      setup_feeds([:gbfs_with_server_error])

      {res, logs} = with_log(fn -> compute_feed_metadata(@gbfs_url, "http://example.com") end)

      assert %{} == res
      assert logs =~ "Could not compute GBFS feed metadata"
    end

    test "for feed with an invalid JSON response" do
      setup_feeds([:gbfs_with_invalid_gbfs_json])
      setup_validation_result({:error, nil})

      {res, logs} = with_log(fn -> compute_feed_metadata(@gbfs_url, "http://example.com") end)

      assert %{} == res
      assert logs =~ "Could not compute GBFS feed metadata"
    end
  end

  describe "versions" do
    test "1.0 feed" do
      json =
        Jason.decode!("""
         {
           "last_updated":1729501544,
           "ttl":0,
           "data":{
              "en":{
                 "feeds":[
                    {
                       "name":"system_information",
                       "url":"https://example.com/gbfs/system_information.json"
                    },
                    {
                       "name":"station_information",
                       "url":"https://example.com/gbfs/station_information.json"
                    },
                    {
                       "name":"station_status",
                       "url":"https://example.com/gbfs/station_status.json"
                    }
                 ]
              }
           }
        }
        """)

      assert ["1.0"] == versions(json)
    end

    test "2.3 feed, no gbfs_versions feed" do
      json =
        Jason.decode!("""
         {
           "last_updated":1729501544,
           "ttl":0,
           "version": "2.3",
           "data":{
              "en":{
                 "feeds":[
                    {
                       "name":"system_information",
                       "url":"https://example.com/gbfs/system_information.json"
                    },
                    {
                       "name":"station_information",
                       "url":"https://example.com/gbfs/station_information.json"
                    },
                    {
                       "name":"station_status",
                       "url":"https://example.com/gbfs/station_status.json"
                    }
                 ]
              }
           }
        }
        """)

      assert ["2.3"] == versions(json)
    end

    test "2.3 feed, gbfs_versions feed" do
      gbfs_versions_url = "https://example.com/gbfs/gbfs_versions"

      setup_response(
        gbfs_versions_url,
        Jason.encode!(%{
          data: %{
            versions: [
              %{version: "2.3"},
              %{version: "3.0"}
            ]
          }
        })
      )

      json =
        Jason.decode!("""
         {
           "last_updated":1729501544,
           "ttl":0,
           "version": "2.3",
           "data":{
              "en":{
                 "feeds":[
                    {
                       "name":"system_information",
                       "url":"https://example.com/gbfs/system_information.json"
                    },
                    {
                       "name":"station_information",
                       "url":"https://example.com/gbfs/station_information.json"
                    },
                    {
                       "name":"station_status",
                       "url":"https://example.com/gbfs/station_status.json"
                    },
                    {
                       "name":"gbfs_versions",
                       "url":"#{gbfs_versions_url}"
                    }
                 ]
              }
           }
        }
        """)

      assert ["3.0", "2.3"] == versions(json)
    end
  end

  describe "feeds" do
    test "3.0 feed" do
      json =
        Jason.decode!("""
         {
          "last_updated": "2023-07-17T13:34:13+02:00",
          "ttl": 0,
          "version": "3.0",
          "data": {
            "feeds": [
              {
                "name": "system_information",
                "url": "https://www.example.com/gbfs/1/system_information"
              },
              {
                "name": "station_information",
                "url": "https://www.example.com/gbfs/1/station_information"
              }
            ]
          }
        }
        """)

      assert ["system_information", "station_information"] == feeds(json)
    end
  end

  describe "vehicle_types" do
    test "3.0 feed, vehicle_types feed present" do
      vehicle_types_url = "https://example.com/gbfs/vehicle_types"

      setup_response(
        vehicle_types_url,
        Jason.encode!(%{
          data: %{
            vehicle_types: [
              %{form_factor: "bicycle"},
              %{form_factor: "scooter_standing"},
              %{form_factor: "bicycle"}
            ]
          }
        })
      )

      json =
        Jason.decode!("""
         {
          "last_updated": "2023-07-17T13:34:13+02:00",
          "ttl": 0,
          "version": "3.0",
          "data": {
            "feeds": [
              {
                "name": "vehicle_types",
                "url": "#{vehicle_types_url}"
              },
              {
                "name": "station_information",
                "url": "https://example.com/gbfs/station_information"
              }
            ]
          }
        }
        """)

      assert MapSet.new(["bicycle", "scooter_standing"]) == json |> vehicle_types() |> MapSet.new()
    end

    test "2.1 feed, vehicle_types feed not present" do
      json =
        Jason.decode!("""
         {
          "last_updated": "1636116522",
          "ttl": 0,
          "version": "2.1",
          "data": {
            "fr": {
              "feeds": [
                {
                  "name": "station_information",
                  "url": "https://example.com/gbfs/station_information"
                }
              ]
            }
          }
        }
        """)

      assert ["bicycle"] == json |> vehicle_types()
    end
  end

  describe "languages" do
    test "3.0 feed" do
      system_information_url = "https://example.com/gbfs/system_information"

      setup_response(system_information_url, Jason.encode!(%{data: %{languages: ["en", "fr"]}}))

      json =
        Jason.decode!("""
         {
          "last_updated": "2023-07-17T13:34:13+02:00",
          "ttl": 0,
          "version": "3.0",
          "data": {
            "feeds": [
              {
                "name": "system_information",
                "url": "#{system_information_url}"
              },
              {
                "name": "station_information",
                "url": "https://example.com/gbfs/station_information"
              }
            ]
          }
        }
        """)

      assert MapSet.new(["en", "fr"]) == json |> languages() |> MapSet.new()
    end

    test "2.3 feed" do
      # Example from https://github.com/MobilityData/gbfs/blob/v2.3/gbfs.md#gbfsjson
      json =
        Jason.decode!("""
        {
          "last_updated": 1640887163,
          "ttl": 0,
          "version": "2.3",
          "data": {
            "en": {
              "feeds": [
                {
                  "name": "system_information",
                  "url": "https://www.example.com/gbfs/1/en/system_information"
                },
                {
                  "name": "station_information",
                  "url": "https://www.example.com/gbfs/1/en/station_information"
                }
              ]
            },
            "fr" : {
              "feeds": [
                {
                  "name": "system_information",
                  "url": "https://www.example.com/gbfs/1/fr/system_information"
                },
                {
                  "name": "station_information",
                  "url": "https://www.example.com/gbfs/1/fr/station_information"
                }
              ]
            }
          }
        }
        """)

      assert MapSet.new(["en", "fr"]) == json |> languages() |> MapSet.new()
    end
  end

  describe "free_bike_status becomes vehicle_status" do
    test "v2.3" do
      assert feed_is_named?(%{"name" => "free_bike_status"}, :vehicle_status)
      assert feed_is_named?(%{"name" => "free_bike_status.json"}, :vehicle_status)

      payload = %{
        "version" => "2.3",
        "data" => %{
          "en" => %{
            "feeds" => [%{"name" => "free_bike_status", "url" => feed_url = "https://example.com/free_bike_status"}]
          }
        }
      }

      assert has_feed?(payload, :vehicle_status)

      assert payload |> first_feed() |> feed_url_by_name(:vehicle_status) == feed_url

      assert has_feed?(
               %{"version" => "2.3", "data" => %{"en" => %{"feeds" => [%{"name" => "free_bike_status.json"}]}}},
               :vehicle_status
             )
    end

    test "v3.0" do
      assert feed_is_named?(%{"name" => "vehicle_status"}, :vehicle_status)

      payload = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [%{"name" => "vehicle_status", "url" => feed_url = "https://example.com/free_bike_status"}]
        }
      }

      assert has_feed?(payload, :vehicle_status)
      assert payload |> first_feed() |> feed_url_by_name(:vehicle_status) == feed_url
    end
  end

  defp setup_validation_result(summary \\ nil) do
    Shared.Validation.GBFSValidator.Mock
    |> expect(:validate, fn url ->
      assert url == @gbfs_url

      default =
        {:ok,
         %GBFSValidationSummary{
           has_errors: false,
           errors_count: 0,
           version_detected: "1.1",
           version_validated: "1.1",
           validator_version: "31c5325",
           validator: :validator_module
         }}

      if is_nil(summary), do: default, else: summary
    end)
  end

  defp setup_feeds(feeds), do: Enum.map(feeds, &setup_feed(&1))

  defp setup_feed(:gbfs), do: setup_gbfs_response()
  defp setup_feed(:gbfs_with_versions), do: setup_gbfs_with_versions_response()
  defp setup_feed(:gbfs_with_server_error), do: setup_gbfs_with_server_error_response()
  defp setup_feed(:gbfs_with_invalid_gbfs_json), do: setup_invalid_gbfs_response()
  defp setup_feed(:gbfs_versions), do: setup_gbfs_versions_response()
  defp setup_feed(:free_bike_status), do: setup_free_bike_status_response()
  defp setup_feed(:system_information), do: setup_system_information_response()
  defp setup_feed(:station_information), do: setup_station_information_response()
  defp setup_feed(:vehicle_types), do: setup_vehicle_types_response()

  defp setup_response_with_headers(expected_url, body) do
    Transport.HTTPoison.Mock
    |> expect(:get, fn url, headers ->
      assert headers == [{"origin", "http://example.com"}]
      assert url == expected_url

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: body,
         headers: [{"Content-Type", "application/json"}, {"Access-Control-Allow-Origin", "*"}]
       }}
    end)
  end

  defp setup_response(expected_url, body) do
    Transport.HTTPoison.Mock
    |> expect(:get, fn url ->
      assert url == expected_url

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: body,
         headers: [{"Content-Type", "application/json"}]
       }}
    end)
  end

  defp setup_gbfs_with_server_error_response do
    Transport.HTTPoison.Mock
    |> expect(:get, fn _url, _headers -> {:ok, %HTTPoison.Response{status_code: 500}} end)
  end

  defp setup_gbfs_response do
    body = """
     {"data":{"fr":{"feeds":[{"name":"system_information","url":"https://example.com/system_information.json"},{"name":"station_information","url":"https://example.com/station_information.json"},{"name":"station_status","url":"https://example.com/station_status.json"}]}},"last_updated":1636116464,"ttl":3600,"version":"1.1"}
    """

    setup_response_with_headers(@gbfs_url, body)
  end

  defp setup_invalid_gbfs_response do
    body = """
    {"foo": "bar"}
    """

    setup_response_with_headers(@gbfs_url, body)
  end

  defp setup_gbfs_with_versions_response do
    body = """
    {"last_updated":1636365542,"ttl":60,"version":"2.2","data":{"fr":{"feeds":[{"name":"system_information.json","url":"https://example.com/system_information.json"},{"name":"free_bike_status.json","url":"https://example.com/free_bike_status.json"},{"name":"vehicle_types.json","url":"https://example.com/vehicle_types.json"},{"name":"system_pricing_plans.json","url":"https://example.com/system_pricing_plans.json"},{"name":"station_information.json","url":"https://example.com/station_information.json"},{"name":"station_status.json","url":"https://example.com/station_status.json"},{"name":"geofencing_zones.json","url":"https://example.com/geofencing_zones.json"},{"name":"gbfs_versions.json","url":"https://example.com/gbfs_versions.json"}]}}}
    """

    setup_response_with_headers(@gbfs_url, body)
  end

  defp setup_gbfs_versions_response do
    body = """
    {"last_updated":1636365614,"ttl":60,"version":"2.2","data":{"versions":[{"version":"2.1","url":"https://data-sharing.tier-services.io/tier_grenoble/gbfs/2.1"},{"version":"2.2","url":"https://data-sharing.tier-services.io/tier_grenoble/gbfs/2.2"}]}}
    """

    setup_response("https://example.com/gbfs_versions.json", body)
  end

  defp setup_free_bike_status_response do
    body = """
    {"last_updated":1636365844,"ttl":60,"version":"2.2","data":{"bikes":[{"bike_id":"e09ff10385b087afd4f69acf4fbabc3bd9c21d23973414a5489ac5364ced407f","lat":45.179489,"lon":5.726216,"is_reserved":false,"is_disabled":false,"vehicle_type_id":"escooter_grenoble","current_range_meters":25564,"pricing_plan_id":"7f500abb-9f84-461a-bc64-e411ddbcf174","rental_uris":{"android":"https://tier.page.link/Vbaff","ios":"https://tier.page.link/Vbaff"}}]}}
    """

    setup_response("https://example.com/free_bike_status.json", body)
  end

  defp setup_system_information_response do
    body = """
     {"data":{"language":"fr","name":"velhop","system_id":"strasbourg","timezone":"Europe/Paris"},"last_updated":1636116522,"ttl":3600,"version":"1.1"}
    """

    setup_response("https://example.com/system_information.json", body)
  end

  defp setup_station_information_response do
    body = """
     {"data":{"stations":[{"capacity":16,"lat":48.568644,"lon":7.795621,"name":"124 Auberge de jeunesse","rental_method":"CREDIT_CARD","station_id":"124"}]},"last_updated":1636116909,"ttl":3600,"version":"1.1"}
    """

    setup_response("https://example.com/station_information.json", body)
  end

  defp setup_vehicle_types_response do
    body = """
     {"data": {"vehicle_types": [{"form_factor": "bicycle","max_range_meters": 20000,"propulsion_type": "electric_assist","vehicle_type_id": "titibike"},{"form_factor": "bicycle","max_range_meters": 60000,"propulsion_type": "electric_assist","vehicle_type_id": "x2"},{"form_factor": "scooter","max_range_meters": 35000,"propulsion_type": "electric","vehicle_type_id": "knot"},{"form_factor": "scooter","max_range_meters": 60000,"propulsion_type": "electric","vehicle_type_id": "pony"}]},"last_updated": "2024-10-16T16:23:49+02:00","ttl": 300,"version": "3.0"}
    """

    setup_response("https://example.com/vehicle_types.json", body)
  end
end
