defmodule Transport.ImportDataServiceTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias Transport.ImportDataService

  doctest ImportDataService

  test "import dataset with a zip" do
    use_cassette "dataset/irigo-1" do
      url = "https://www.data.gouv.fr/s/resources/horaires-et-arrets-du-reseau-irigo-format-gtfs/20170130-094427/Keolis_Irigo_Angers_20170129-20170409.zip"
      assert {:ok, dataset} = ImportDataService.import_from_udata("horaires-et-arrets-du-reseau-irigo-format-gtfs")
      assert dataset["download_uri"] == url
    end
  end

  test "import dataset with GTFS format" do
    use_cassette "dataset/metz-2" do
      url = "https://si.metzmetropole.fr/fiches/opendata/gtfs_current.zip"
      assert {:ok, dataset} = ImportDataService.import_from_udata("transport-donnees-gtfs")
      assert dataset["download_uri"] == url
    end
  end

  test "import dataset with CSV" do
    use_cassette "dataset/ter-3" do
      url = "https://ressources.data.sncf.com/api/v2/catalog/datasets/sncf-ter-gtfs/files/24e02fa969496e2caa5863a365c66ec2"
      assert {:ok, dataset} = ImportDataService.import_from_udata("horaires-des-lignes-ter-sncf")
      assert dataset["download_uri"] == url
    end
  end
end
