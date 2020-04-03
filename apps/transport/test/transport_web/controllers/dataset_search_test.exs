defmodule TransportWeb.DatasetSearchControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias DB.{AOM, Dataset, Repo, Resource, Validation}

  doctest TransportWeb.DatasetController

  setup do
    {:ok, _} =
      %Dataset{
        description: "Un jeu de données",
        licence: "odc-odbl",
        title: "Horaires et arrêts du réseau IRIGO - format GTFS",
        spatial: "Horaires Angers",
        type: "public-transit",
        slug: "horaires-et-arrets-du-reseau-irigo-format-gtfs",
        datagouv_id: "5b4cd3a0b59508054dd496cd",
        frequency: "yearly",
        tags: [],
        resources: [
          %Resource{
            url: "https://link.to/angers.zip",
            validation: %Validation{},
            metadata: %{},
            title: "angers.zip",
            auto_tags: ["ferry"]
          }
        ],
        aom: %AOM{id: 4242, nom: "Angers Métropôle"}
      }
      |> Repo.insert()

    {:ok, _} =
      %Dataset{
        description: "Un autre jeu de données",
        licence: "odc-odbl",
        title: "offre de transport du réseau de LAVAL Agglomération (GTFS)",
        slug: "offre-de-transport-du-reseau-de-laval-agglomeration-gtfs",
        type: "public-transit",
        datagouv_id: "5bc493d08b4c416c84a69500",
        frequency: "yearly",
        tags: [],
        resources: [
          %Resource{
            url: "https://link.to/angers.zip",
            validation: %Validation{},
            metadata: %{}
          }
        ]
      }
      |> Repo.insert()

    :ok
  end

  test "GET /datasets", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "2 résultats de recherche"
  end

  test "GET /datasets?type=unknown_type", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{type: "soucoupe-volante"})
    assert html_response(conn, 200) =~ "0 résultat de recherche"
  end

  test "GET /datasets?type=public-transit", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit"})
    assert html_response(conn, 200) =~ "2 résultats de recherche"
  end

  test "GET /datasets?tags[]=unknown", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{tags: ["unknown"]})
    assert html_response(conn, 200) =~ "0 résultat de recherche"
  end

  test "GET /datasets?tags[]=ferry", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{tags: ["ferry"]})
    assert html_response(conn, 200) =~ "1 résultat de recherche"
  end

  test "GET /datasets/aom/4242", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :by_aom, 4242))
    assert html_response(conn, 200) =~ "Jeux de données de l&#39;AOM Angers Métropôle"
  end

  test "GET /datasets/aom/999999", %{conn: conn} do
    # searching for an unknown AOM should lead to a 404
    conn = conn |> get(dataset_path(conn, :by_aom, 999_999))
    assert html_response(conn, 404)
  end
end
