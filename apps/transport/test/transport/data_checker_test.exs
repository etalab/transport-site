defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import Mox

  import Transport.DataChecker, only: [compute_gbfs_feed_meta: 1]

  @gbfs_url "https://example.com/gbfs.json"

  setup :verify_on_exit!

  describe "Compute GBFS metadata for a feed" do
    test "for a stations feed with a single version" do
      setup_feeds([:gbfs, :system_information, :station_information])

      expected = %{
        languages: ["fr"],
        system_details: %{name: "velhop", timezone: "Europe/Paris"},
        ttl: 3600,
        types: ["stations"],
        versions: ["1.1"]
      }

      assert expected == compute_gbfs_feed_meta(%DB.Resource{url: @gbfs_url})
    end
  end

  defp setup_feeds(feeds) do
    feeds
    |> Enum.map(fn feed ->
      case feed do
        :gbfs -> setup_gbfs_response()
        :system_information -> setup_system_information_response()
        :station_information -> setup_station_information_response()
      end
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

  defp setup_gbfs_response do
    body = """
     {"data":{"fr":{"feeds":[{"name":"system_information","url":"https://example.com/system_information.json"},{"name":"station_information","url":"https://example.com/station_information.json"},{"name":"station_status","url":"https://example.com/station_status.json"}]}},"last_updated":1636116464,"ttl":3600,"version":"1.1"}
    """

    setup_response(@gbfs_url, body)
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
