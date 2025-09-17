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
      declarative_spatial_areas: [
        %DB.AdministrativeDivision{
          type: :epci,
          type_insee: "epci",
          insee: "123456",
          geom: %Geo.Point{coordinates: {1, 1}, srid: 4326},
          nom: "Angers Métropôle"
        }
      ],
      aom: %DB.AOM{id: 4242, nom: "Angers Métropôle AOM"}
    )

    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)

    :ok
  end

  test "GET / ", %{conn: conn} do
    title = conn |> get(~p"/") |> html_response(200) |> title
    assert title =~ "Le Point d’Accès National aux données ouvertes de transport"
  end

  test "GET /datasets ", %{conn: conn} do
    title = conn |> get(dataset_path(conn, :index)) |> html_response(200) |> title
    assert title =~ "Le Point d’Accès National aux données ouvertes de transport"
  end

  test "GET /datasets/region/52 ", %{conn: conn} do
    region = Repo.get_by(Region, nom: "Pays de la Loire")
    title = conn |> get(~p"/datasets/region/#{region.insee}") |> html_response(200) |> title
    assert title =~ "Jeux de données ouverts de la région Pays de la Loire"
  end

  test "GET /datasets/departement/76 ", %{conn: conn} do
    insert(:departement, insee: "76", nom: "Seine Maritime")
    title = conn |> get(~p"/datasets/departement/76") |> html_response(200) |> title
    assert title =~ "Département Seine Maritime : Jeux de données ouverts"
  end

  test "GET /datasets/epci/4242 ", %{conn: conn} do
    insert(:epci, insee: "4242", nom: "Angers Métropôle")
    title = conn |> get(~p"/datasets/epci/4242") |> html_response(200) |> title
    assert title =~ "EPCI Angers Métropôle : Jeux de données ouverts"
  end

  test "GET /datasets/commune/36044 ", %{conn: conn} do
    title = conn |> get(~p"/datasets/commune/36044") |> html_response(200) |> title
    assert title =~ "Jeux de données ouverts de la commune de Châteauroux"
  end

  test "GET /landing-vls", %{conn: conn} do
    title = conn |> get(~p"/landing-vls") |> html_response(200) |> title
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

  test "GET /espace_reutilisateur", %{conn: conn} do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    assert "Espace réutilisateur" ==
             conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> get(reuser_space_path(conn, :espace_reutilisateur))
             |> html_response(200)
             |> title()
  end

  defp title(page) do
    page |> Floki.parse_document!() |> Floki.find("title") |> Floki.text()
  end
end
