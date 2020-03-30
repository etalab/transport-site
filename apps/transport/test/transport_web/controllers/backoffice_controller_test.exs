defmodule TransportWeb.BackofficeControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias DB.{Repo, Resource}
  import Ecto.Repo

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
             "Vous devez remplir soit une région soit une AOM soit utiliser les zones data.gouv"
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
             "Vous devez remplir soit une région soit une AOM soit utiliser les zones data.gouv"
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

    conn =
      use_cassette "dataset/dataset-region.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert Resource |> Repo.all() |> length() == 1
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

    conn =
      use_cassette "dataset/dataset-aom.json" do
        post(conn, backoffice_dataset_path(conn, :post), dataset)
      end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)

    assert Resource |> Repo.all() |> length() == 1
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
