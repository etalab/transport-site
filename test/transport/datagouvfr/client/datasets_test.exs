defmodule Transport.Datagouvfr.Client.DatasetsTest do
  use TransportWeb.ConnCase, async: false # smell
  use TransportWeb.ExternalCase # smell
  alias Transport.Datagouvfr.Client
  alias Transport.Datagouvfr.Client.Datasets
  alias Transport.Datagouvfr.Authentication

  doctest Client

  test "get one dataset" do
    use_cassette "client/datasets/one-0" do
      assert {:ok, data} = Datasets.get(build_conn(), "horaires-et-arrets-du-reseau-irigo-format-gtfs")
      assert data |> Map.get("resources") |> List.first() |> Map.get("url") =~ "zip"
    end
  end

  test "get datasets of an organization old format" do
    use_cassette "client/datasets/organization-datasets-1" do
      assert {:ok, data} = Datasets.get(build_conn(),
                             %{:organization => "538346d6a3a72906c7ec5c36"})
      assert data |> Enum.any?(fn(d) -> d["id"] == "5387f0a0a3a7291cb367549e" end)
    end
  end

  test "get datasets of an organization new format" do
    use_cassette "client/datasets/organization-datasets-6" do
      assert {:ok, data} = Datasets.get(build_conn(),
                             %{:organization => "538346d6a3a72906c7ec5c36"})
      assert Enum.empty?(data)
    end
  end

  test "Add a tag to a dataset" do
    use_cassette "client/datasets/put-add-tag-2" do
      conn = build_conn() |> assign(:client, Authentication.client("secret"))
      assert {:ok, data} = Datasets.put(conn, "le-plan-de-transport-de-ma-commune", {:add_tag, "montag"})
      assert data |> Map.get("tags") |> Enum.member?("montag")
    end
  end

  test "put dataset" do
    use_cassette "client/datasets/put-3" do
      conn = build_conn() |> assign(:client, Authentication.client("secret"))
      {:ok, dataset} = Datasets.get(conn, "le-plan-de-transport-de-ma-commune")
      dataset = Map.put(dataset, "title", "modified")
      assert {:ok, dataset} = Datasets.put(conn, "le-plan-de-transport-de-ma-commune", dataset)
      assert dataset |> Map.get("title") =~ "modified"
    end
  end

  test "post dataset" do
    use_cassette "client/datasets/post-4" do
      params = %{
        "description"  => "desc",
        "frequency"    => "monthly",
        "licence"      => "ODbl",
        "organization" => "name-2",
        "title"        => "title"
      }
      conn = build_conn() |> assign(:client, Authentication.client("secret"))
      assert {:ok, dataset} = Datasets.post(conn, params)
      assert dataset |> Map.get("title") =~ "title"
    end
  end

  test "upload resource" do
    use_cassette "client/datasets/upload_resource-5" do
      upload = %Plug.Upload{path: "test/fixture/files/gtfs.zip",
                            filename: "gtfs.zip"}
      conn = build_conn() |> assign(:client, Authentication.client("secret"))
      assert {:ok, dataset} = Datasets.upload_resource(conn,
                              "un-nouveau-jeu-6", upload)
      assert dataset |> Map.get("title") =~ "gtfs.zip"
    end
  end
end
