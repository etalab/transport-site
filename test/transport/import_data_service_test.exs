defmodule Transport.ImportDataServiceTest do
  use ExUnit.Case, async: true
  alias Transport.ImportDataService

  @moduletag :external

  describe "import_from_udata" do
    test "import dataset with a zip" do
      url = "http://hstan.g-ny.org/grandnancy/data/public/gtfs_stan.zip"
      assert {:ok, dataset} = ImportDataService.import_from_udata("arrets-horaires-et-parcours-theoriques-du-reseau-stan-gtfs", "transport-statique")
      assert dataset["download_url"] == url
    end

    test "import dataset with GTFS format" do
      url = "https://si.metzmetropole.fr/fiches/opendata/gtfs_current.zip"
      assert {:ok, dataset} = ImportDataService.import_from_udata("transport-donnees-gtfs", "transport-statique")
      assert dataset["download_url"] == url
    end

    test "import dataset with CSV" do
      url = "https://ressources.data.sncf.com/api/v2/catalog/datasets/sncf-ter-gtfs/files/24e02fa969496e2caa5863a365c66ec2"
      assert {:ok, dataset} = ImportDataService.import_from_udata("horaires-des-lignes-ter-sncf", "transport-statique")
      assert dataset["download_url"] == url
    end

  end
end
