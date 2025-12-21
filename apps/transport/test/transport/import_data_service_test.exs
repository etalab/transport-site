defmodule Transport.ImportDataServiceTest do
  use ExUnit.Case, async: true
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
  end
end
