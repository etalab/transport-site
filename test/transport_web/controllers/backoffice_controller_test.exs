defmodule TransportWeb.BackofficeControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias Transport.{Repo, Resource}
  import Ecto.Repo

  test "Add a dataset with a region and AOM", %{conn: conn} do
    conn = use_cassette "session/create-2" do
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))
    end

    dataset_url = "https://next.data.gouv.fr/fr/datasets/arrets-horaires-et-circuits-impulsyon-a-la-roche-sur-yon-gtfs-5/"
    dataset = %{
      "url" => dataset_url,
      "spatial" => "La Roche sur Yon",
      "region_id" => 1,
      "insee_commune_principale" => "85191",
      "type" => "public-transit",
      "action" => "new"
    }
    conn = use_cassette "dataset/impulsyon.json-1" do
      post(conn, backoffice_dataset_path(conn, :post), dataset)
    end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert from(r in Resource) |> Repo.all() |> length() == 0
    assert get_flash(conn, :error) =~ "Impossible"
    assert get_flash(conn, :error) =~ "région"
    assert get_flash(conn, :error) =~ "AOM"
  end

  test "Add a dataset without a region nor aom", %{conn: conn} do
    conn = use_cassette "session/create-2" do
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))
    end

    dataset_url = "https://next.data.gouv.fr/fr/datasets/arrets-horaires-et-circuits-impulsyon-a-la-roche-sur-yon-gtfs-5/"
    dataset = %{
      "url" => dataset_url,
      "spatial" => "La Roche sur Yon",
      "region_id" => nil,
      "insee_commune_principale" => nil,
      "type" => "public-transit",
      "action" => "new"
    }
    conn = use_cassette "dataset/impulsyon.json-1" do
      post(conn, backoffice_dataset_path(conn, :post), dataset)
    end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert from(r in Resource) |> Repo.all() |> length() == 0
    assert get_flash(conn, :error) =~ "Impossible"
    assert get_flash(conn, :error) =~ "région"
    assert get_flash(conn, :error) =~ "AOM"
  end

  test "Add a dataset without a region and no aom", %{conn: conn} do
    conn = use_cassette "session/create-2" do
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))
    end

    dataset_url = "https://next.data.gouv.fr/fr/datasets/arrets-horaires-et-circuits-impulsyon-a-la-roche-sur-yon-gtfs-5/"
    dataset = %{
      "url" => dataset_url,
      "spatial" => "La Roche sur Yon",
      "region_id" => Repo.get_by(Region, nom: "Pays de la Loire").id,
      "insee_commune_principale" => nil,
      "type" => "public-transit",
      "action" => "new"
    }
    conn = use_cassette "dataset/impulsyon.json-1" do
      post(conn, backoffice_dataset_path(conn, :post), dataset)
    end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert from(r in Resource) |> Repo.all() |> length() == 1
    assert get_flash(conn, :info) =~ "ajouté"
  end

  test "Add a dataset without no region and a aom", %{conn: conn} do
    conn = use_cassette "session/create-2" do
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))
    end

    dataset_url = "https://next.data.gouv.fr/fr/datasets/arrets-horaires-et-circuits-impulsyon-a-la-roche-sur-yon-gtfs-5/"
    dataset = %{
      "url" => dataset_url,
      "spatial" => "La Roche sur Yon",
      "region_id" => Repo.get_by(Region, nom: "Pays de la Loire").id,
      "insee_commune_principale" => nil,
      "type" => "public-transit",
      "action" => "new"
    }
    conn = use_cassette "dataset/impulsyon.json-1" do
      post(conn, backoffice_dataset_path(conn, :post), dataset)
    end

    assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
    assert from(r in Resource) |> Repo.all() |> length() == 1
    assert get_flash(conn, :info) =~ "ajouté"
  end

  test "Add a dataset twice", %{conn: conn} do
    conn = use_cassette "session/create-2" do
      conn
      |> init_test_session(redirect_path: "/datasets")
      |> get(session_path(conn, :create, %{"code" => "secret"}))
    end

    dataset_url = "https://next.data.gouv.fr/fr/datasets/arrets-horaires-et-circuits-impulsyon-a-la-roche-sur-yon-gtfs-5/"
    resource_url = "https://data.loire-atlantique.fr/api/datasets/1.0/248500589_arrets-horaires-et-circuits-impulsyon-gtfs_lrsya/alternative_exports/gtfs_impulsyon_zip"
    dataset = %{
      "url" => dataset_url,
      "spatial" => "La Roche sur Yon",
      "region_id" => nil,
      "insee_commune_principale" => "85191",
      "type" => "public-transit",
      "action" => "new"
    }

    use_cassette "dataset/impulsyon.json-1" do
      conn = post(conn, backoffice_dataset_path(conn, :post), dataset)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert from(r in Resource, where: r.url == ^resource_url) |> Repo.all() |> length() == 1

      conn = post(conn, backoffice_dataset_path(conn, :post), dataset)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert from(r in Resource, where: r.url == ^resource_url) |> Repo.all() |> length() == 1
    end
  end
end
