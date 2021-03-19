defmodule TransportWeb.NavTest do
  use TransportWeb.ConnCase, async: true
  alias DB.{AOM, Dataset, Repo, Resource, Validation}
  import Mock

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

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
            title: "angers.zip"
          }
        ],
        aom: %AOM{nom: "Angers Métropôle"}
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

  def click_link_by_text(conn, html, text) do
    doc = Floki.parse_document!(html)
    [link] = Floki.find(doc, "a:fl-contains('#{text}')")
    [href] = Floki.attribute(link, "href")
    conn |> get(href)
  end

  test "I can list available datasets to find and download transport data", %{conn: conn} do
    # NOTE: we cannot easily mock the API exchanges, so just stubbing the known bits for now, and
    # we'll later use a proper stubbed implementation for all tests.
    with_mock Datagouvfr.Client.Discussions, get: fn _ -> [] end do
      # browse the home
      conn = conn |> get("/")
      html = html_response(conn, 200)

      # I can click to the a list of available datasets
      conn = click_link_by_text(conn, html, "Voir les jeux de données récents")
      html = html_response(conn, 200)

      # I can see or read somewhere that the datasets are valid
      assert html =~ "Jeux de données"
      conn = click_link_by_text(conn, html, "Horaires Angers")
      html = html_response(conn, 200)

      assert html =~ "Horaires Angers"
      assert html =~ "Un jeu de données"

      doc = Floki.parse_document!(html)

      # I can download the dataset
      [element] = Floki.find(doc, ".download-button")
      [href] = Floki.attribute(element, "href")
      assert String.ends_with?(href, ".zip")
    end
  end
end
