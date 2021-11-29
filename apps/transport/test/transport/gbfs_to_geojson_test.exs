defmodule Transport.GbfsToGeojsonTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  describe "gbfs to geojson conversion" do
    test "station_information conversion" do
    gbfs_endpoint = "gbfs.json"
    Transport.HTTPoison.Mock |> expect(:get!, fn ^gbfs_endpoint ->
      %{status_code: 200, body: """
        {
        "data": {
          "fr": {
            "feeds": [
              {
                "name": "station_information",
                "url": "station_information.json"
              }
            ]
          }
        }
      }
      """
      }
    end)

    set_station_information_expect()

    geojsons = Transport.GbfsToGeojson.gbfs_geojsons(gbfs_endpoint)
    assert geojsons["stations"] ==
      [
        %{
          "geometry" => %{
            "coordinates" => ["-2.3353", "47.26095"],
            "type" => "Point"
          },
          "properties" => %{
            "name" => "Rond-point de l'Hippodrome",
            "station_id" => "stn_VWFEvC9XWrvmE2m7kkFkKo"
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
            "station_id" => "stn_TdAEzFgrkvHXmQ3U8nRxtt"
          },
          "type" => "Feature"
        }
      ]
    end
  end

  defp set_station_information_expect() do
    Transport.HTTPoison.Mock |> expect(:get!, fn "station_information.json" ->
    %{status_code: 200, body: """
      {
        "data": {
          "stations": [
            {
              "lat": "47.26095",
              "lon": "-2.3353",
              "name": "Rond-point de l'Hippodrome",
              "station_id": "stn_VWFEvC9XWrvmE2m7kkFkKo"
            },
            {
              "lat": "47.270352",
              "lon": "-2.345135",
              "name": "Gare de Pornichet",
              "station_id": "stn_TdAEzFgrkvHXmQ3U8nRxtt"
            }
          ]
        }
      }
      """
      }
    end)
  end
end
