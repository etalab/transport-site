defmodule Transport.GBFSMetadataTest do
  # async: false is required because we use real in-memory caching in these tests
  use ExUnit.Case, async: false
  import Mox
  import Transport.GBFSMetadata
  import ExUnit.CaptureLog
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary

  doctest Transport.GBFSMetadata, import: true

  @gbfs_url "https://example.com/gbfs.json"

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Use a real in-memory cache for these tests to test the caching mecanism
    old_value = Application.fetch_env!(:transport, :cache_impl)
    Application.put_env(:transport, :cache_impl, Transport.Cache.Cachex)

    on_exit(fn ->
      Application.put_env(:transport, :cache_impl, old_value)
      Cachex.reset(Transport.Cache.Cachex.cache_name())
    end)
  end

  describe "Compute GBFS metadata for a feed" do
    test "for a stations feed with a single version" do
      setup_feeds([:gbfs, :system_information, :station_information, :station_status])
      setup_validation_result()

      assert %{
               languages: ["fr"],
               system_details: %{
                 "language" => "fr",
                 "name" => "velhop",
                 "system_id" => "strasbourg",
                 "timezone" => "Europe/Paris"
               },
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
               feed_timestamp_delay: _,
               vehicle_types: ["bicycle"],
               stats: %{
                 nb_docks_available: 11,
                 nb_docks_disabled: 2,
                 nb_installed_stations: 2,
                 nb_renting_stations: 2,
                 nb_returning_stations: 2,
                 nb_stations: 2,
                 nb_vehicles_available_stations: 7,
                 nb_vehicles_disabled_stations: 3,
                 version: 2
               },
               operator: "Example"
             } = compute_feed_metadata(@gbfs_url)
    end

    test "for a stations + free floating feed with multiple versions" do
      setup_feeds([
        :gbfs_with_versions,
        :gbfs_versions,
        :system_information,
        :vehicle_types,
        :station_information,
        :free_bike_status,
        :station_status
      ])

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
               system_details: %{
                 "language" => "fr",
                 "name" => "velhop",
                 "system_id" => "strasbourg",
                 "timezone" => "Europe/Paris"
               },
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
               feed_timestamp_delay: feed_timestamp_delay,
               vehicle_types: ["bicycle", "scooter"],
               stats: %{
                 nb_docks_available: 11,
                 nb_docks_disabled: 2,
                 nb_installed_stations: 2,
                 nb_renting_stations: 2,
                 nb_returning_stations: 2,
                 nb_stations: 2,
                 nb_vehicles_available_stations: 7,
                 nb_vehicles_disabled_stations: 3,
                 version: 2
               },
               operator: "Example"
             } = compute_feed_metadata(@gbfs_url)

      assert feed_timestamp_delay > 0
    end

    test "for feed with a 500 error on the root URL" do
      setup_feeds([:gbfs_with_server_error])

      {res, logs} = with_log(fn -> compute_feed_metadata(@gbfs_url) end)

      assert %{} == res
      assert logs =~ "Could not compute GBFS feed metadata"
    end

    test "for feed with an invalid JSON response" do
      setup_feeds([:gbfs_with_invalid_gbfs_json])
      setup_validation_result({:error, nil})

      {res, logs} = with_log(fn -> compute_feed_metadata(@gbfs_url) end)

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

  describe "system_details" do
    test "2.3 feed" do
      system_information_url = "https://example.com/gbfs/system_information"

      setup_response(
        system_information_url,
        """
        {
          "last_updated": 1729517006,
          "ttl": 0,
          "version": "2.3",
          "data": {
            "email": "support@ecovelo.com",
            "feed_contact_email": "gbfs@ecovelo.com",
            "language": "fr",
            "name": "Vélycéo",
            "phone_number": "+33974591314",
            "purchase_url": "https://velyceo.ecovelo.mobi/#/forfaits",
            "start_date": "2020-08-20",
            "system_id": "velyceo",
            "timezone": "Europe/Paris",
            "url": "https://velyceo.ecovelo.mobi"
          }
        }
        """
      )

      json =
        Jason.decode!("""
         {
          "last_updated": 1729517006,
          "ttl": 0,
          "version": "2.3",
          "data": {
            "en": {
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
        }
        """)

      assert %{
               "email" => "support@ecovelo.com",
               "feed_contact_email" => "gbfs@ecovelo.com",
               "language" => "fr",
               "name" => "Vélycéo",
               "phone_number" => "+33974591314",
               "purchase_url" => "https://velyceo.ecovelo.mobi/#/forfaits",
               "start_date" => "2020-08-20",
               "system_id" => "velyceo",
               "timezone" => "Europe/Paris",
               "url" => "https://velyceo.ecovelo.mobi"
             } == json |> system_details()
    end

    test "3.0 feed" do
      system_information_url = "https://example.com/gbfs/system_information"

      setup_response(
        system_information_url,
        """
        {
          "data": {
            "email": "support@ecovelo.com",
            "feed_contact_email": "gbfs@ecovelo.com",
            "languages": [
              "fr"
            ],
            "manifest_url": "https://api.gbfs.ecovelo.mobi/manifest.json",
            "name": [
              {
                "language": "fr",
                "text": "V\u00e9lYc\u00e9o"
              }
            ],
            "opening_hours": "24/7",
            "phone_number": "+33974591314",
            "purchase_url": "https://velyceo.ecovelo.mobi/#/forfaits",
            "start_date": "2020-08-20",
            "system_id": "velyceo",
            "terms_last_updated": "2022-04-01",
            "terms_url": [
              {
                "language": "fr",
                "text": "https://velyceo.ecovelo.mobi/#/cgu"
              }
            ],
            "timezone": "Europe/Paris",
            "url": "https://velyceo.ecovelo.mobi"
          },
          "last_updated": "2024-10-21T15:31:51+02:00",
          "ttl": 300,
          "version": "3.0"
        }
        """
      )

      json =
        Jason.decode!("""
         {
          "last_updated": "2024-10-21T15:31:51+02:00",
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

      assert %{
               "email" => "support@ecovelo.com",
               "feed_contact_email" => "gbfs@ecovelo.com",
               "name" => "VélYcéo",
               "phone_number" => "+33974591314",
               "purchase_url" => "https://velyceo.ecovelo.mobi/#/forfaits",
               "start_date" => "2020-08-20",
               "system_id" => "velyceo",
               "timezone" => "Europe/Paris",
               "url" => "https://velyceo.ecovelo.mobi",
               "languages" => ["fr"],
               "manifest_url" => "https://api.gbfs.ecovelo.mobi/manifest.json",
               "opening_hours" => "24/7",
               "terms_last_updated" => "2022-04-01",
               "terms_url" => "https://velyceo.ecovelo.mobi/#/cgu"
             } == json |> system_details()
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

      assert payload |> feed_url_by_name(:vehicle_status) == feed_url

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
      assert payload |> feed_url_by_name(:vehicle_status) == feed_url
    end
  end

  describe "stats" do
    test "3.0 feed" do
      setup_response("https://example.com/gbfs/station_status", fixture_content("station_status.3.0"))
      setup_response("https://example.com/gbfs/vehicle_status", fixture_content("vehicle_status.3.0"))

      # Values may not make sense: responses have been taken from the GBFS spec
      # and edited to make sure we test various possibilities without having massive
      # fixture files.
      assert %{
               nb_disabled_vehicles: 1,
               nb_docked_vehicles: 1,
               nb_docks_available: 11,
               nb_docks_disabled: 2,
               nb_freefloating_vehicles: 1,
               nb_installed_stations: 2,
               nb_renting_stations: 2,
               nb_reserved_vehicles: 1,
               nb_returning_stations: 2,
               nb_stations: 2,
               nb_vehicles: 2,
               version: 2,
               nb_vehicles_available_stations: 7,
               nb_vehicles_disabled_stations: 3,
               nb_virtual_stations: 1
             } == stats(fixture_content("gbfs.3.0") |> Jason.decode!())
    end

    test "2.2 feed" do
      setup_response("https://example.com/gbfs/station_status", fixture_content("station_status.2.2"))
      setup_response("https://example.com/gbfs/free_bike_status", fixture_content("free_bike_status.2.2"))

      # Values may not make sense: responses have been taken from the GBFS spec
      # and edited to make sure we test various possibilities without having massive
      # fixture files.
      assert %{
               nb_disabled_vehicles: 0,
               nb_docked_vehicles: 1,
               nb_docks_available: 11,
               nb_docks_disabled: 1,
               nb_freefloating_vehicles: 1,
               nb_installed_stations: 2,
               nb_renting_stations: 2,
               nb_reserved_vehicles: 0,
               nb_returning_stations: 2,
               nb_stations: 2,
               nb_vehicles: 2,
               nb_vehicles_available_stations: 7,
               nb_vehicles_disabled_stations: 0,
               nb_virtual_stations: 0,
               version: 2
             } == stats(fixture_content("gbfs.2.2") |> Jason.decode!())
    end
  end

  describe "types" do
    test "vehicles feed with no station information and stations feeds should be considered mixed type" do
      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{data: %{stations: [%{station_id: Ecto.UUID.generate()}]}})
      )

      # `station_id` is not present in the response, the bike is considered as free floating
      setup_response(
        vehicle_status_url = "https://example.com/vehicle_status",
        Jason.encode!(%{data: %{vehicles: [%{bike_id: Ecto.UUID.generate()}]}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status", "url" => vehicle_status_url},
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert ["free_floating", "stations"] == types(gbfs_url)
    end

    test "vehicles and stations feeds, empty stations should be considered as free floating" do
      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{data: %{stations: []}})
      )

      setup_response(
        vehicle_status_url = "https://example.com/vehicle_status",
        Jason.encode!(%{data: %{vehicles: [%{bike_id: Ecto.UUID.generate()}]}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status", "url" => vehicle_status_url},
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert ["free_floating"] == types(gbfs_url)
    end

    test "vehicles and stations feeds, vehicles are docked" do
      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{data: %{stations: [%{station_id: Ecto.UUID.generate()}]}})
      )

      setup_response(
        vehicle_status_url = "https://example.com/vehicle_status",
        Jason.encode!(%{data: %{vehicles: [%{station_id: Ecto.UUID.generate()}]}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status", "url" => vehicle_status_url},
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert ["stations"] == types(gbfs_url)
    end

    test "vehicles and stations feeds, no vehicles" do
      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{data: %{stations: [%{station_id: Ecto.UUID.generate()}]}})
      )

      setup_response(
        vehicle_status_url = "https://example.com/vehicle_status",
        Jason.encode!(%{data: %{vehicles: []}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status", "url" => vehicle_status_url},
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert ["stations"] == types(gbfs_url)
    end

    test "stations feed only" do
      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{data: %{stations: [%{station_id: Ecto.UUID.generate()}]}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert ["stations"] == types(gbfs_url)
    end

    test "vehicles feed only" do
      setup_response(
        vehicle_status_url = "https://example.com/vehicle_status",
        Jason.encode!(%{data: %{vehicles: [%{bike_id: Ecto.UUID.generate()}]}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status", "url" => vehicle_status_url}
          ]
        }
      }

      assert ["free_floating"] == types(gbfs_url)
    end

    test "stations feed with only virtual stations should be considered as free floating" do
      station_id = Ecto.UUID.generate()

      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{data: %{stations: [%{station_id: station_id, is_virtual_station: true}]}})
      )

      setup_response(
        vehicle_status_url = "https://example.com/vehicle_status",
        Jason.encode!(%{data: %{vehicles: [%{station_id: station_id}]}})
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status", "url" => vehicle_status_url},
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert ["free_floating"] == types(gbfs_url)
    end
  end

  describe "virtual_station_ids" do
    test "no station_information feed" do
      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "vehicle_status"}
          ]
        }
      }

      assert [] == virtual_station_ids(gbfs_url)
    end

    test "identifies IDs" do
      virtual_station_id = Ecto.UUID.generate()
      physical_station_id = Ecto.UUID.generate()

      setup_response(
        station_information_url = "https://example.com/station_information",
        Jason.encode!(%{
          data: %{
            stations: [
              %{station_id: virtual_station_id, is_virtual_station: true},
              %{station_id: physical_station_id}
            ]
          }
        })
      )

      gbfs_url = %{
        "version" => "3.0",
        "data" => %{
          "feeds" => [
            %{"name" => "station_information", "url" => station_information_url}
          ]
        }
      }

      assert [virtual_station_id] == virtual_station_ids(gbfs_url)
    end
  end

  defp fixture_content(filename) do
    File.read!("#{__DIR__}/../fixture/gbfs/#{filename}.json")
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
  defp setup_feed(:station_status), do: setup_station_status_response()

  defp setup_response(expected_url, body) do
    Transport.HTTPoison.Mock
    |> expect(:get, fn ^expected_url ->
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: [{"content-type", "application/json"}]}}
    end)
  end

  defp setup_gbfs_with_server_error_response do
    Transport.HTTPoison.Mock
    |> expect(:get, fn _url -> {:ok, %HTTPoison.Response{status_code: 500}} end)
  end

  defp setup_gbfs_response do
    body = """
     {"data":{"fr":{"feeds":[{"name":"system_information","url":"https://example.com/system_information.json"},{"name":"station_information","url":"https://example.com/station_information.json"},{"name":"station_status","url":"https://example.com/station_status.json"}]}},"last_updated":1636116464,"ttl":3600,"version":"1.1"}
    """

    setup_response(@gbfs_url, body)
  end

  defp setup_invalid_gbfs_response do
    body = """
    {"foo": "bar"}
    """

    setup_response(@gbfs_url, body)
  end

  defp setup_gbfs_with_versions_response do
    body = """
    {"last_updated":1636365542,"ttl":60,"version":"2.2","data":{"fr":{"feeds":[{"name":"system_information.json","url":"https://example.com/system_information.json"},{"name":"free_bike_status.json","url":"https://example.com/free_bike_status.json"},{"name":"vehicle_types.json","url":"https://example.com/vehicle_types.json"},{"name":"system_pricing_plans.json","url":"https://example.com/system_pricing_plans.json"},{"name":"station_information.json","url":"https://example.com/station_information.json"},{"name":"station_status.json","url":"https://example.com/station_status.json"},{"name":"geofencing_zones.json","url":"https://example.com/geofencing_zones.json"},{"name":"gbfs_versions.json","url":"https://example.com/gbfs_versions.json"}]}}}
    """

    setup_response(@gbfs_url, body)
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

  defp setup_station_status_response do
    body = """
     {"last_updated":"2023-07-17T13:34:13+02:00","ttl":0,"version":"3.0","data":{"stations":[{"station_id":"station1","is_installed":true,"is_renting":true,"is_returning":true,"last_reported":"2023-07-17T13:34:13+02:00","num_docks_available":3,"num_docks_disabled":1,"vehicle_docks_available":[{"vehicle_type_ids":["abc123","def456"],"count":2},{"vehicle_type_ids":["def456"],"count":1}],"num_vehicles_available":1,"num_vehicles_disabled":2,"vehicle_types_available":[{"vehicle_type_id":"abc123","count":1},{"vehicle_type_id":"def456","count":0}]},{"station_id":"station2","is_installed":true,"is_renting":true,"is_returning":true,"last_reported":"2023-07-17T13:34:13+02:00","num_docks_available":8,"num_docks_disabled":1,"vehicle_docks_available":[{"vehicle_type_ids":["abc123"],"count":6},{"vehicle_type_ids":["def456"],"count":2}],"num_vehicles_available":6,"num_vehicles_disabled":1,"vehicle_types_available":[{"vehicle_type_id":"abc123","count":2},{"vehicle_type_id":"def456","count":4}]}]}}
    """

    setup_response("https://example.com/station_status.json", body)
  end
end
