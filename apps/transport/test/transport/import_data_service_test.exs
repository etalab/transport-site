defmodule Transport.ImportDataServiceTest do
  use ExUnit.Case, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ExternalCase
  alias Transport.ImportData

  @moduletag :external

  describe "import_from_data_gouv" do
    test "import dataset with a zip" do
      url = "http://hstan.g-ny.org/grandnancy/data/public/gtfs_stan.zip"

      use_cassette "client/datasets/stan" do
        assert {:ok, dataset} =
                 ImportData.import_from_data_gouv(
                   "arrets-horaires-et-parcours-theoriques-du-reseau-stan-gtfs",
                   "public-transit"
                 )

        assert List.first(dataset["resources"])["url"] == url
      end
    end

    test "import dataset with GTFS format" do
      url = "https://si.metzmetropole.fr/fiches/opendata/gtfs_current.zip"

      use_cassette "client/datasets/metz" do
        assert {:ok, dataset} = ImportData.import_from_data_gouv("transport-donnees-gtfs", "public-transit")
        assert List.first(dataset["resources"])["url"] == url
      end
    end

    test "import dataset with CSV" do
      url =
        "https://ressources.data.sncf.com/api/v2/catalog/datasets/sncf-ter-gtfs/files/24e02fa969496e2caa5863a365c66ec2"

      use_cassette "client/datasets/sncf" do
        assert {:ok, dataset} = ImportData.import_from_data_gouv("horaires-des-lignes-ter-sncf", "public-transit")

        assert length(dataset["resources"]) == 1
        resource = List.first(dataset["resources"])
        assert resource["url"] == url
        assert resource["datagouv_id"] == "28a42d49-e9a8-4c6c-a999-b2b7ea8ce977"
      end
    end
  end
end
