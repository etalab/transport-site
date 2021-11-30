defmodule Transport.GbfsToGeojsonTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  describe "gbfs to geojson conversion" do
    test "station_information conversion" do
      gbfs_endpoint = "gbfs.json"
      feeds = [%{"name" => "station_information", "url" => "station_information.json"}]

      set_gbfs_entrypoint_expect(gbfs_endpoint, feeds)
      set_station_information_expect()

      geojsons = Transport.GbfsToGeojson.gbfs_geojsons(gbfs_endpoint)
      assert geojsons["stations"] == simple_station_information_geojson()
    end

    test "station_information + station_status conversion" do
      gbfs_endpoint = "gbfs.json"

      feeds = [
        %{"name" => "station_information", "url" => "station_information.json"},
        %{"name" => "station_status", "url" => "station_status.json"}
      ]

      set_gbfs_entrypoint_expect(gbfs_endpoint, feeds)
      set_station_information_expect()
      set_station_status_expect()

      geojsons = Transport.GbfsToGeojson.gbfs_geojsons(gbfs_endpoint)

      assert geojsons["stations"] ==
               %{
                 "type" => "FeatureCollection",
                 "features" => [
                   %{
                     "geometry" => %{
                       "coordinates" => ["-2.3353", "47.26095"],
                       "type" => "Point"
                     },
                     "properties" => %{
                       "name" => "Rond-point de l'Hippodrome",
                       "station_id" => "1",
                       "station_status" => %{
                         "num_bikes_available" => 0,
                         "num_docks_available" => 0,
                         "a_field" => "coucou"
                       }
                     },
                     "type" => "Feature"
                   },
                   %{
                     "geometry" => %{
                       "coordinates" => ["-2.345135", "47.270352"],
                       "type" => "Point"
                     },
                     "properties" => %{
                       "name" => "Gare de Pornichet",
                       "station_id" => "2",
                       "station_status" => %{
                         "num_bikes_available" => 3,
                         "num_docks_available" => 12,
                         "num_vehicles_available" => 3
                       }
                     },
                     "type" => "Feature"
                   }
                 ]
               }
    end


    test "station_information + failing station_status conversion" do
      gbfs_endpoint = "gbfs.json"

      feeds = [
        %{"name" => "station_information", "url" => "station_information.json"},
        %{"name" => "station_status", "url" => "station_status.json"}
      ]

      set_gbfs_entrypoint_expect(gbfs_endpoint, feeds)
      set_station_information_expect()
      set_station_status_expect("bad response")

      geojsons = Transport.GbfsToGeojson.gbfs_geojsons(gbfs_endpoint)

      # if the station_status is not valid, you should still have a basic geojson
      # from station_information
      assert geojsons["stations"] == simple_station_information_geojson()
    end

  end

  defp simple_station_information_geojson() do
    %{
      "type" => "FeatureCollection",
      "features" => [
        %{
          "geometry" => %{
            "coordinates" => ["-2.3353", "47.26095"],
            "type" => "Point"
          },
          "properties" => %{
            "name" => "Rond-point de l'Hippodrome",
            "station_id" => "1"
          },
          "type" => "Feature"
        },
        %{
          "geometry" => %{
            "coordinates" => ["-2.345135", "47.270352"],
            "type" => "Point"
          },
          "properties" => %{
            "name" => "Gare de Pornichet",
            "station_id" => "2"
          },
          "type" => "Feature"
        }
      ]
    }
  end

  defp set_gbfs_entrypoint_expect(entrypoint_url, feeds) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^entrypoint_url ->
      %{status_code: 200, body: gbfs_entry_point(feeds)}
    end)
  end

  defp gbfs_entry_point(feeds) do
    %{
      "data" => %{
        "fr" => %{
          "feeds" => feeds
        }
      }
    }
    |> Jason.encode!()
  end

  defp set_station_information_expect() do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn "station_information.json" ->
      %{
        status_code: 200,
        body: """
        {
          "data": {
            "stations": [
              {
                "lat": "47.26095",
                "lon": "-2.3353",
                "name": "Rond-point de l'Hippodrome",
                "station_id": "1"
              },
              {
                "lat": "47.270352",
                "lon": "-2.345135",
                "name": "Gare de Pornichet",
                "station_id": "2"
              }
            ]
          }
        }
        """
      }
    end)
  end

  defp set_station_status_expect(custom_response \\ nil) do

    Transport.HTTPoison.Mock
    |> expect(:get!, fn "station_status.json" ->
      custom_response ||
      %{
        status_code: 200,
        body: """
        {
          "data": {
            "stations": [
              {
                "num_bikes_available": 0,
                "num_docks_available": 0,
                "a_field": "coucou",
                "station_id": "1"
              },
              {
                "num_bikes_available": 3,
                "num_docks_available": 12,
                "num_vehicles_available": 3,
                "station_id": "2"
              },
              {
                "num_bikes_available": 16,
                "station_id": "does not exist"
              }
            ]
          }
        }
        """
      }
    end)
  end
end
