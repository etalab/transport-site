defmodule TransportWeb.NavTest do
  # NOTE: temporarily set to false, until it doesn't use with_mock anymore
  use TransportWeb.ConnCase, async: false
  import DB.Factory
  import Mock
  import Mox

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    insert(:dataset,
      description: "Un jeu de données",
      spatial: "Horaires Angers",
      resources: [
        build(:resource, url: "https://link.to/angers.zip")
      ],
      aom: build(:aom)
    )

    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)

    :ok
  end

  def click_link_by_text(conn, html, text) do
    doc = Floki.parse_document!(html)
    [link] = Floki.find(doc, "a:fl-contains('#{text}')")
    [href] = Floki.attribute(link, "href")
    conn |> get(href)
  end

  test "I can list available datasets to find and download transport data", %{conn: conn} do
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _ -> [] end)
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
