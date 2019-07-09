defmodule Datagouvfr.Client.DatasetsTest do
  use TransportWeb.ConnCase, async: false # smell
  use TransportWeb.ExternalCase # smell
  alias Datagouvfr.Client
  alias Datagouvfr.Client.Datasets

  doctest Client

  test "get one dataset" do
    use_cassette "client/datasets/one-0" do
      assert {:ok, data} = Datasets.get("horaires-et-arrets-du-reseau-irigo-format-gtfs")
      assert data |> Map.get("resources") |> List.first() |> Map.get("url") =~ "zip"
    end
  end

  test "get datasets of an organization old format" do
    use_cassette "client/datasets/organization-datasets-1" do
      assert {:ok, data} = Datasets.get(%{:organization => "538346d6a3a72906c7ec5c36"})
      assert data |> Enum.any?(fn(d) -> d["id"] == "5387f0a0a3a7291cb367549e" end)
    end
  end

  test "get datasets of an organization new format" do
    use_cassette "client/datasets/organization-datasets-6" do
      assert {:ok, data} = Datasets.get(%{:organization => "538346d6a3a72906c7ec5c36"})
      assert Enum.empty?(data)
    end
  end
end
