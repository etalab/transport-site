defmodule Transport.Jobs.GBFSStationsToGeoDataTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.GBFSStationsToGeoData
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "relevant_gbfs_urls" do
    gbfs_1 = insert(:resource, format: "gbfs", url: "https://example.com/gbfs_1")
    gbfs_2 = insert(:resource, format: "gbfs", url: "https://example.com/gbfs_2")
    gbfs_3 = insert(:resource, format: "gbfs", url: "https://example.com/gbfs_3")
    gbfs_4 = insert(:resource, format: "gbfs", url: "https://example.com/gbfs_4")

    ten_days_ago = DateTime.utc_now() |> DateTime.add(-10, :day)
    five_days_ago = DateTime.utc_now() |> DateTime.add(-5, :day)

    # `gbfs_1` is relevant but should not be duplicated
    insert(:resource_metadata, resource_id: gbfs_1.id, metadata: %{types: ["stations"]}, inserted_at: five_days_ago)
    insert(:resource_metadata, resource_id: gbfs_1.id, metadata: %{types: ["stations"]})
    # `gbfs_4` should be included: stations + free floating
    insert(:resource_metadata, resource_id: gbfs_4.id, metadata: %{types: ["free_floating", "stations"]})

    # Ignored: too old
    insert(:resource_metadata, resource_id: gbfs_2.id, metadata: %{types: ["stations"]}, inserted_at: ten_days_ago)
    # Ignored: no stations
    insert(:resource_metadata,
      resource_id: gbfs_3.id,
      metadata: %{types: ["free_floating"]},
      inserted_at: five_days_ago
    )

    result = GBFSStationsToGeoData.relevant_gbfs_urls()
    assert Enum.count(result) == 2
    assert [gbfs_1.url, gbfs_4.url] |> MapSet.new() == result |> MapSet.new()
  end

  describe "perform" do
    test "imports stations data from 2 feeds" do
      assert DB.GeoData |> DB.Repo.all() |> Enum.empty?()
      assert DB.GeoDataImport |> DB.Repo.all() |> Enum.empty?()

      gbfs_1 = insert(:resource, format: "gbfs", url: "https://example.com/gbfs_1")
      gbfs_2 = insert(:resource, format: "gbfs", url: "https://example.com/gbfs_2")
      station_info_url_1 = "https://example.com/station_info_url_1"
      station_info_url_2 = "https://example.com/station_info_url_2"

      insert(:resource_metadata,
        resource_id: gbfs_1.id,
        metadata: %{types: ["stations"]},
        inserted_at: DateTime.utc_now() |> DateTime.add(-5, :day)
      )

      insert(:resource_metadata, resource_id: gbfs_2.id, metadata: %{types: ["free_floating", "stations"]})

      assert [gbfs_1.url, gbfs_2.url] |> MapSet.new() == GBFSStationsToGeoData.relevant_gbfs_urls() |> MapSet.new()

      setup_responses(%{
        gbfs_1.url => %{
          "version" => "3.0",
          "data" => %{"feeds" => [%{"name" => "station_information", "url" => station_info_url_1}]}
        },
        station_info_url_1 => %{
          "version" => "3.0",
          "data" => %{
            "stations" => [
              %{
                "capacity" => 30,
                "is_valet_station" => false,
                "is_virtual_station" => false,
                "lat" => 47.26095,
                "lon" => -2.3353,
                "name" => [
                  %{
                    "language" => "fr",
                    "text" => "Rond-point"
                  }
                ]
              }
            ]
          }
        },
        gbfs_2.url => %{
          "version" => "3.0",
          "data" => %{"feeds" => [%{"name" => "station_information", "url" => station_info_url_2}]}
        },
        station_info_url_2 => %{
          "version" => "3.0",
          "data" => %{
            "stations" => [
              %{
                "capacity" => 20,
                "is_valet_station" => false,
                "is_virtual_station" => false,
                "lat" => 45.4542,
                "lon" => 2.6278,
                "name" => [
                  %{
                    "language" => "fr",
                    "text" => "Gare"
                  }
                ]
              },
              # Ignored: virtual station
              %{
                "capacity" => 10,
                "is_virtual_station" => true,
                "lat" => 2,
                "lon" => 1,
                "name" => [
                  %{
                    "language" => "fr",
                    "text" => "Bistrot"
                  }
                ]
              },
              # Ignored: latitude is nil
              %{
                "capacity" => 10,
                "lat" => nil,
                "lon" => 1,
                "name" => [
                  %{
                    "language" => "fr",
                    "text" => "Pub"
                  }
                ]
              },
              # Ignored: no coordinates
              %{
                "capacity" => 10,
                "name" => [
                  %{
                    "language" => "fr",
                    "text" => "Bar"
                  }
                ]
              }
            ]
          }
        }
      })

      assert :ok == perform_job(GBFSStationsToGeoData, %{})

      %DB.GeoDataImport{id: geo_data_import_id} = DB.Repo.get_by!(DB.GeoDataImport, slug: :gbfs_stations)

      assert [
               %DB.GeoData{
                 geom: %Geo.Point{coordinates: {2.6278, 45.4542}, srid: 4326},
                 payload: %{"capacity" => 20, "name" => "Gare"},
                 geo_data_import_id: ^geo_data_import_id
               },
               %DB.GeoData{
                 geom: %Geo.Point{coordinates: {-2.3353, 47.26095}, srid: 4326},
                 payload: %{"capacity" => 30, "name" => "Rond-point"},
                 geo_data_import_id: ^geo_data_import_id
               }
             ] = DB.GeoData |> DB.Repo.all() |> Enum.sort_by(& &1.payload["capacity"])
    end

    test "replaces existing data" do
      geo_data_import = %DB.GeoDataImport{slug: :gbfs_stations} |> DB.Repo.insert!()

      %DB.GeoData{
        geom: %Geo.Point{coordinates: {2.6278, 45.4542}, srid: 4326},
        payload: %{"capacity" => 20, "name" => "Gare"},
        geo_data_import_id: geo_data_import.id
      }
      |> DB.Repo.insert!()

      # No GBFS metadata for stations, existing data should be deleted after running the job

      assert [] == GBFSStationsToGeoData.relevant_gbfs_urls()

      assert :ok == perform_job(GBFSStationsToGeoData, %{})

      assert DB.GeoData |> DB.Repo.all() |> Enum.empty?()
    end
  end

  defp setup_responses(responses) do
    expect(Transport.HTTPoison.Mock, :get, Enum.count(responses), fn url ->
      body = Map.fetch!(responses, url) |> Jason.encode!()
      {:ok, %HTTPoison.Response{status_code: 200, body: body, headers: [{"content-type", "application/json"}]}}
    end)
  end
end
