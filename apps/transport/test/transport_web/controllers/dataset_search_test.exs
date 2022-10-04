defmodule TransportWeb.DatasetSearchControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
  alias DB.{AOM, Dataset, Repo, Resource, Validation}

  doctest TransportWeb.DatasetController

  setup do
    {:ok, _} =
      %Dataset{
        description: "Un jeu de données",
        licence: "odc-odbl",
        datagouv_title: "Horaires et arrêts du réseau IRIGO - format GTFS",
        custom_title: "Horaires Angers",
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
            modes: ["ferry"],
            features: ["tarifs"]
          }
        ],
        aom: %AOM{id: 4242, nom: "Angers Métropôle"}
      }
      |> Repo.insert()

    {:ok, _} =
      %Dataset{
        description: "Un autre jeu de données",
        licence: "lov2",
        datagouv_title: "offre de transport du réseau de LAVAL Agglomération (GTFS)",
        custom_title: "Horaires Laval",
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

  test "GET /datasets title", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    # titre de la page
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "GET /datasets filter", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    # info dans les filtres à gauche des datasets
    assert html_response(conn, 200) =~ "Transport public collectif - horaires théoriques (2)"
  end

  test "GET /datasets?modes[]=ferry", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{modes: ["ferry"]})
    assert html_response(conn, 200) =~ "Transport public collectif - horaires théoriques (1)"
  end

  test "GET /datasets?features[]=tarifs", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{features: ["tarifs"]})
    assert html_response(conn, 200) =~ "Transport public collectif - horaires théoriques (1)"
  end

  test "GET /datasets?type=public-transit", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit"})
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "GET /datasets?type=public-transit&licence=odc-odbl", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit", licence: "odc-odbl"})
    assert html_response(conn, 200) =~ "Transport public collectif - horaires théoriques (1)"
    assert html_response(conn, 200) =~ "Horaires Angers"
    refute html_response(conn, 200) =~ "Horaires Laval"

    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit", licence: "licence-ouverte"})
    assert html_response(conn, 200) =~ "Horaires Laval"
    refute html_response(conn, 200) =~ "Horaires Angers"
  end

  test "GET /datasets/aom/4242", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :by_aom, 4242))
    assert html_response(conn, 200) =~ "AOM"
    assert html_response(conn, 200) =~ "Angers Métropôle"
  end

  test "GET /datasets/aom/999999", %{conn: conn} do
    # searching for an unknown AOM should lead to a 404
    conn = conn |> get(dataset_path(conn, :by_aom, 999_999))
    assert html_response(conn, 404)
  end

  test "a dataset labelled as base nationale published by us is first without filters" do
    %{id: base_nationale_dataset_id} =
      insert(:dataset,
        type: "public-transit",
        custom_title: "Base nationale des GTFS",
        organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
      )

    results = %{"type" => "public-transit"} |> Dataset.list_datasets() |> Repo.all()
    assert Enum.count(results) == 3
    assert %Dataset{id: ^base_nationale_dataset_id} = hd(results)

    %{id: first_dataset_id} =
      %{"type" => "public-transit", "q" => "angers"} |> Dataset.list_datasets() |> Repo.all() |> hd()

    assert first_dataset_id != base_nationale_dataset_id
  end
end
