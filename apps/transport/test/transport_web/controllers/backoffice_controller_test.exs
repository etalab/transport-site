defmodule TransportWeb.BackofficeControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias DB.{Repo, Resource}

  import Mox
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Datagouvfr.Client.CommunityResources.Mock, Datagouvfr.Client.StubCommunityResources)

    # ressource.db now uses Transport.Wrapper.HTTPoison instead of HTTPoison directly
    # we stub the mock with the real module here to keep the tests of this file unchanged.
    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)
    :ok
  end

  @dataset_url "https://demo.data.gouv.fr/fr/datasets/horaires-theoriques-du-reseau-de-transport-tag-1/"
  @dataset %{
    "url" => @dataset_url,
    "spatial" => "Grenoble",
    "region_id" => 1,
    "insee" => "38185",
    "type" => "public-transit",
    "action" => "new"
  }

  @dataset_with_zones_url "https://demo.data.gouv.fr/fr/datasets/test-jeux-de-donnees-associe-a-plusieurs-villes/"
  @dataset_with_zones %{
    "url" => @dataset_with_zones_url,
    "spatial" => "Grenoble",
    "type" => "public-transit",
    "action" => "new"
  }

  test "Deny access to backoffice if not logged", %{conn: conn} do
    conn = get(conn, backoffice_page_path(conn, :index))
    target_uri = URI.parse(redirected_to(conn, 302))
    assert target_uri.path == "/login/explanation"
    assert target_uri.query == URI.encode_query(redirect_path: "/backoffice")
    assert get_flash(conn, :info) =~ "Vous devez être préalablement connecté"
  end

  test "Check that you belong to the right organization", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{current_user: %{"organizations" => [%{"slug" => "pouet pouet"}]}})
      |> get(backoffice_page_path(conn, :index))

    assert redirected_to(conn, 302) =~ "/login/explanation"
    assert get_flash(conn, :error) =~ "You need to be a member of the transport.data.gouv.fr team."
  end

  test "Show 'add new dataset' form", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{
        current_user: %{"organizations" => [%{"slug" => "blurp"}, %{"slug" => "equipe-transport-data-gouv-fr"}]}
      })
      |> get(backoffice_page_path(conn, :index))

    assert html_response(conn, 200) =~ "Ajouter un jeu de données"
  end

  @tag :external
  test "Add a dataset with a region and AOM", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    conn =
      use_cassette "dataset/dataset-region-ao.json" do
        post(conn, backoffice_dataset_path(conn, :post), @dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 0

    assert get_flash(conn, :error) ==
             "%{region: [\"Vous devez remplir soit une région soit une AOM soit utiliser les zones data.gouv\"]}"
  end

  @tag :external
  test "Add a dataset without a region nor aom", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset = @dataset |> Map.put("region_id", nil) |> Map.put("insee", nil)

    conn =
      use_cassette "dataset/dataset-no-region-nor-ao.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 0

    assert get_flash(conn, :error) ==
             "%{region: [\"Vous devez remplir soit une région soit une AOM soit utiliser les zones data.gouv\"]}"
  end

  @tag :external
  test "Add a dataset linked to a region", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset =
      @dataset
      |> Map.put("region_id", Repo.get_by(Region, nom: "Auvergne-Rhône-Alpes").id)
      |> Map.put("insee", nil)

    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn id ->
      # we return the same urls that the one we find in dataset-region.json cassette
      # because for the moment the Hasher is not Mocked
      # we it is the case, we will be able to put random urls here
      assert id == "5760038cc751df708cac31a0"

      {:ok,
       [
         %{
           "url" => "https://app-be8e53a7-9b77-4f95-bea0-681b97077017.cleverapps.io/metromobilite/gtfs-rt.json",
           "id" => "r1"
         },
         %{
           "url" => "https://app-be8e53a7-9b77-4f95-bea0-681b97077017.cleverapps.io/metromobilite/gtfs-rt",
           "id" => "r2"
         }
       ]}
    end)

    conn =
      use_cassette "dataset/dataset-region.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> where([r], not r.is_community_resource) |> Repo.all() |> length() == 1
    assert Resource |> where([r], r.is_community_resource) |> Repo.all() |> length() == 2
    assert get_flash(conn, :info) =~ "ajouté"
  end

  @tag :external
  test "Add a dataset linked to aom", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset = %{@dataset | "region_id" => nil}

    Datagouvfr.Client.CommunityResources.Mock
    |> expect(:get, fn id ->
      # we return the same urls that the one we find in dataset-aom.json cassette
      # because for the moment the Hasher is not Mocked
      # we it is the case, we will be able to put random urls here
      assert id == "5760038cc751df708cac31a0"

      {:ok,
       [
         %{
           "url" => "https://app-be8e53a7-9b77-4f95-bea0-681b97077017.cleverapps.io/metromobilite/gtfs-rt.json",
           "id" => "r1"
         },
         %{
           "url" => "https://app-be8e53a7-9b77-4f95-bea0-681b97077017.cleverapps.io/metromobilite/gtfs-rt",
           "id" => "r2"
         }
       ]}
    end)

    conn =
      use_cassette "dataset/dataset-aom.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)

    assert Resource |> where([r], not r.is_community_resource) |> Repo.all() |> length() == 1
    assert Resource |> where([r], r.is_community_resource) |> Repo.all() |> length() == 2
    assert get_flash(conn, :info) =~ "ajouté"
  end

  @tag :external
  test "Add a dataset linked to cities", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset =
      @dataset_with_zones
      |> Map.put("region_id", nil)
      |> Map.put("insee", nil)
      |> Map.put("associated_territory_name", "pouet")

    conn =
      use_cassette "dataset/dataset-with-multiple-cities.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 1
    assert get_flash(conn, :info) =~ "ajouté"
  end

  @tag :external
  test "Add a dataset linked to cities and to the country", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset =
      @dataset_with_zones
      |> Map.put("region_id", nil)
      |> Map.put("insee", nil)
      |> Map.put("associated_territory_name", "pouet")
      |> Map.put("national_dataset", "true")

    conn =
      use_cassette "dataset/dataset-with-multiple-cities-and-country.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    # It should not be possible to link a dataset to either
    # a list of cities and to the whole country
    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 0
    flash = get_flash(conn, :error)

    assert flash =~
             "Vous devez remplir soit une région soit une AOM soit utiliser les zones data.gouv"
  end

  @tag :external
  test "Add a dataset linked to an AO and with an empty territory name", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset =
      @dataset_with_zones
      |> Map.put("region_id", nil)
      |> Map.put("associated_territory_name", "")
      |> Map.put("national_dataset", "true")

    conn =
      use_cassette "dataset/dataset-with-multiple-cities.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    # It should be possible to link a dataset to an AOM if the territory name
    # is empty (but not null since it comes from a form)
    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 1
    assert get_flash(conn, :info) =~ "ajouté"
  end

  @tag :external
  test "Add a dataset linked to a region and to the country", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    dataset =
      @dataset
      |> Map.put("region_id", 1)
      |> Map.put("insee", nil)
      |> Map.put("national_dataset", "true")

    conn =
      use_cassette "dataset/dataset-region-and-country.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    # It should not be possible to link a dataset to either a region and to the whole country
    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 0
    flash = get_flash(conn, :error)
    assert flash =~ "Un jeu de données ne pas pas être à la fois régional et national"
  end

  @tag :external
  test "Add a dataset twice", %{conn: conn} do
    conn =
      use_cassette "session/create-2" do
        conn
        |> init_test_session(redirect_path: "/datasets")
        |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

    resource_url = "http://www.metromobilite.fr/data/Horaires/SEM-GTFS.zip"
    dataset = %{@dataset | "region_id" => nil}

    use_cassette "dataset/dataset_twice" do
      conn = post(conn, backoffice_dataset_path(conn, :post), dataset)
      query = from(r in Resource, where: r.url == ^resource_url)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert query |> Repo.all() |> length() == 1

      conn = post(conn, backoffice_dataset_path(conn, :post), dataset)
      query = from(r in Resource, where: r.url == ^resource_url)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert query |> Repo.all() |> length() == 1
    end
  end
end
