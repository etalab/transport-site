defmodule TransportWeb.SeoMetadataTest do
  @moduledoc """
  test seo metadata
  """
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    Mox.stub_with(Datagouvfr.Client.Reuses.Mock, Datagouvfr.Client.Reuses.Dummy)
    Mox.stub_with(Datagouvfr.Client.Discussions.Mock, Datagouvfr.Client.Discussions.Dummy)
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)

    insert(:dataset,
      created_at: DateTime.utc_now(),
      last_update: DateTime.utc_now(),
      datagouv_title: "Horaires et arrêts du réseau IRIGO - format GTFS",
      custom_title: "Horaires Angers",
      type: "public-transit",
      slug: "horaires-et-arrets-du-reseau-irigo-format-gtfs",
      resources: [
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "https://link.to/angers.zip",
          description: "blabla on resource",
          format: "GTFS",
          title: "angers.zip",
          id: 1234
        }
      ],
      aom: %DB.AOM{id: 4242, nom: "Angers Métropôle"}
    )

    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)

    :ok
  end

  defp title(page) do
    ~r|.*<title>(.*)</title>.*|
    |> Regex.run(page)
    |> case do
      [_ | [title | _]] -> title
      # if not found return all
      _ -> page
    end
  end

  test "GET / ", %{conn: conn} do
    title = conn |> get(~p"/") |> html_response(200) |> title
    assert title =~ "Le Point d’Accès National aux données ouvertes de transport"
  end

  test "GET /datasets ", %{conn: conn} do
    title = conn |> get(dataset_path(conn, :index)) |> html_response(200) |> title
    assert title =~ "Le Point d’Accès National aux données ouvertes de transport"
  end

  test "GET /datasets/aom/4242 ", %{conn: conn} do
    title = conn |> get(~p"/datasets/aom/4242") |> html_response(200) |> title
    assert title =~ "AOM Angers Métropôle : Jeux de données ouverts"
  end

  test "GET /datasets/region/12 ", %{conn: conn} do
    region = Repo.get_by(Region, nom: "Pays de la Loire")
    title = conn |> get(~p"/datasets/region/#{region.id}") |> html_response(200) |> title
    assert title =~ "Jeux de données ouverts de la région Pays de la Loire"
  end

  test "GET /datasets/commune/36044 ", %{conn: conn} do
    title = conn |> get(~p"/datasets/commune/36044") |> html_response(200) |> title
    assert title =~ "Jeux de données ouverts de la commune de Châteauroux"
  end

  test "GET /datasets?type=bike-scooter-sharing ", %{conn: conn} do
    title = conn |> get(~p"/datasets?type=bike-scooter-sharing") |> html_response(200) |> title
    assert title =~ "Jeux de données ouverts de la catégorie Vélos et trottinettes en libre-service"
  end

  test "GET /dataset/:id ", %{conn: conn} do
    Transport.History.Fetcher.Mock |> expect(:history_resources, fn _, _ -> [] end)
    title = conn |> get(~p"/datasets/horaires-et-arrets-du-reseau-irigo-format-gtfs") |> html_response(200) |> title
    assert title =~ "Horaires Angers - Données (GTFS) ouvertes - Angers Métropôle"
  end

  test "GET /resources/:id ", %{conn: conn} do
    title = conn |> get(~p"/resources/1234") |> html_response(200) |> title
    assert title =~ "Jeu de données ouvert GTFS - angers.zip pour Horaires Angers - Angers Métropôle"
  end

  test "GET /aoms ", %{conn: conn} do
    title = conn |> get(~p"/aoms") |> html_response(200) |> title
    assert title =~ "État de l’ouverture des données de transport en commun pour les AOMs françaises"
  end

  test "GET /validation ", %{conn: conn} do
    Transport.Shared.Schemas.Mock |> expect(:transport_schemas, fn -> %{} end)
    title = conn |> get(~p"/validation") |> html_response(200) |> title
    assert title =~ "Évaluation de la qualité d’un fichier ou d’un flux"
  end
end
