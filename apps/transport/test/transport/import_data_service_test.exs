defmodule Transport.ImportDataServiceTest do
  use ExUnit.Case, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ExternalCase
  alias Transport.ImportData
  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub_with(
      Datagouvfr.Client.CommunityResources.Mock,
      Datagouvfr.Client.StubCommunityResources
    )

    Mox.stub_with(Transport.AvailabilityChecker.Mock, Transport.AvailabilityChecker.Dummy)
    Mox.stub_with(Hasher.Mock, Hasher.Dummy)
    :ok
  end

  describe "import_from_data_gouv" do
    test "import dataset with GTFS format" do
      resource_url = "https://si.eurometropolemetz.eu/fiches/opendata/gtfs_current.zip"

      Transport.HTTPoison.Mock
      |> expect(:get!, fn "https://demo.data.gouv.fr/api/1/datasets/transport-donnees-gtfs/", _, _ ->
        %{status: 200, body: ~s({
          "id": "546609c1c751df1a6f6c8d07",
          "resources": [
              {
                "filetype": "remote",
                "type": "main",
                "format": "gtfs",
                "latest": "https://demo.data.gouv.fr/fr/datasets/r/9bff120f-d1ba-4753-83cb-6d598ebe2e60",
                "url": "#{resource_url}",
                "id": "9bff120f-d1ba-4753-83cb-6d598ebe2e60"
              }
          ],
          "slug": "transport-donnees-gtfs"
        })}
      end)

      assert {:ok, dataset} = ImportData.import_from_data_gouv("transport-donnees-gtfs", "public-transit")

      assert List.first(dataset["resources"])["url"] == resource_url
    end

    test "import dataset with CSV (ODS)" do
      resource_final_url =
        "https://ressources.data.sncf.com/api/v2/catalog/datasets/sncf-ter-gtfs/files/24e02fa969496e2caa5863a365c66ec2"

      resource_datagouv_id = "9bff120f-d1ba-4753-83cb-6d598ebe2e60"

      # data.gouv api call
      Transport.HTTPoison.Mock
      |> expect(
        :get!,
        fn "https://demo.data.gouv.fr/api/1/datasets/horaires-des-lignes-ter-sncf/", _, _ ->
          # one resource of the dataset is a csv
          %{status: 200, body: ~s({
          "id": "546609c1c751df1a6f6c8d07",
          "resources": [
              {
                "filetype": "remote",
                "type": "main",
                "format": "csv",
                "mime": "text/csv",
                "latest": "https://url-csv-file",
                "url": "https://url-csv-file",
                "id": "#{resource_datagouv_id}"
              }
          ],
          "slug": "transport-donnees-gtfs"
        })}
        end
      )

      # the csv is downloaded and read
      Transport.HTTPoison.Mock
      |> expect(
        :get,
        3,
        fn "https://url-csv-file", _, _ ->
          {:ok,
           %{
             status_code: 200,
             headers: [{"Content-Type", "csv"}],
             body: ~s(Donnees;format;Download\r\nHoraires des lignes TER;GTFS;#{resource_final_url}\r\n)
           }}
        end
      )

      # we try to guess the name of the downloaded file from the headers
      Transport.HTTPoison.Mock
      |> expect(
        :head,
        3,
        fn ^resource_final_url ->
          {:ok,
           %{
             status_code: 200,
             headers: [{"Content-Disposition", "attachment; filename=\"sncf-ter-gtfs.csv\""}]
           }}
        end
      )

      assert {:ok, dataset} = ImportData.import_from_data_gouv("horaires-des-lignes-ter-sncf", "public-transit")

      assert length(dataset["resources"]) == 1
      resource = List.first(dataset["resources"])
      # the url of the resource has been found in the csv
      assert resource["url"] == resource_final_url
      assert resource["datagouv_id"] == resource_datagouv_id
    end
  end
end
