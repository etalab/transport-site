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

      expected = %{
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
          validator: :validator_module
        },
        has_cors: true,
        is_cors_allowed: true
      }

      assert expected == compute_feed_metadata(@gbfs_url, "http://example.com")
    end

    test "for a stations + free floating feed with a multiple versions" do
      setup_feeds([:gbfs_with_versions, :gbfs_versions, :system_information, :free_bike_status])

      setup_validation_result(
        {:ok, summary} =
          {:ok,
           %GBFSValidationSummary{
             errors_count: 0,
             has_errors: false,
             version_detected: "2.2",
             version_validated: "2.2",
             validator: :validator_module
           }}
      )

      expected = %{
        languages: ["fr"],
        system_details: %{name: "velhop", timezone: "Europe/Paris"},
        ttl: 60,
        types: ["free_floating", "stations"],
        validation: summary,
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
        has_cors: true,
        is_cors_allowed: true
      }

      assert expected == compute_feed_metadata(@gbfs_url, "http://example.com")
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
           validator: :validator_module
         }}

      if is_nil(summary), do: default, else: summary
    end)
  end

  defp setup_feeds(feeds) do
    feeds
    |> Enum.map(fn feed ->
      case feed do
        :gbfs -> setup_gbfs_response()
        :gbfs_with_versions -> setup_gbfs_with_versions_response()
        :gbfs_with_server_error -> setup_gbfs_with_server_error_response()
        :gbfs_with_invalid_gbfs_json -> setup_invalid_gbfs_response()
        :gbfs_versions -> setup_gbfs_versions_response()
        :free_bike_status -> setup_free_bike_status_response()
        :system_information -> setup_system_information_response()
        :station_information -> setup_station_information_response()
      end
    end)
  end

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
end
