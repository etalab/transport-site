defmodule TransportWeb.BackofficeControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  alias Transport.{Repo, Resource}
  import Ecto.Repo

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
      "type" => "transport-statique"
    }

    use_cassette "dataset/impulsyon.json-1" do
      conn = post(conn, dataset_path(conn, :new_dataset), dataset)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert from(r in Resource, where: r.url == ^resource_url) |> Repo.all() |> length() == 1

      conn = post(conn, dataset_path(conn, :new_dataset), dataset)
      assert redirected_to(conn, 302) == backoffice_page_path(conn, :index)
      assert from(r in Resource, where: r.url == ^resource_url) |> Repo.all() |> length() == 1
    end
  end

end
