defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  alias Transport.Datagouvfr.Authentication

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données valides disponibles"
  end

  describe "GET /user/organizations/:organization/datasets/_create" do
    test "logged in", %{conn: conn} do
      use_cassette "dataset/create-0" do
        file = %Plug.Upload{path: "test/fixture/files/gtfs.zip",
                          filename: "gtfs.zip"}
        path = dataset_path(conn, :create, "name-2")
        params = %{
          "description"  => "desc",
          "frequency"    => "monthly",
          "dataset"      => file,
          "licence"      => "ODbl",
          "organization" => "name-2",
          "title"        => "title"
        }
        conn = conn
        |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
        |> post(path, params)
        assert redirected_to(conn, 302) == user_path(conn, :add_badge_dataset, "title-3")
      end
    end

    test "not logged in", %{conn: conn} do
      path = dataset_path(conn, :create, "name-2")
      conn = conn |> post(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end

    @tag :pending
    test "field missing"
  end

  describe "POST /user/organizations/:organization/datasets/_create_community_resource" do
    test "logged in", %{conn: conn} do
      use_cassette "dataset/create-community-resource-4" do
        linked_dataset_slug = "horaires-theoriques-du-reseau-de-transport-lva"
        linked_dataset_id = "5a26e9da0b5b39443a3b56d8"
        file = %Plug.Upload{path: "test/fixture/files/gtfs.zip",
                          filename: "gtfs.zip"}
        organization = "5a16ee520b5b39245053b052"
        path = dataset_path(conn, :create_community_resource, organization)
        params = %{
          "description"  => "desc",
          "dataset"      => file,
          "licence"      => "ODbl",
          "organization" => organization,
          "title"        => "title"
        }
        conn = conn
        |> init_test_session(
             current_user: %{},
             client: Authentication.client("secret"),
             linked_dataset_id: linked_dataset_id,
             linked_dataset_slug: linked_dataset_slug)
        |> post(path, params)
        assert redirected_to(conn, 302) == dataset_path(conn, :details, linked_dataset_slug)
      end
    end

    test "not logged in", %{conn: conn} do
      path = dataset_path(conn, :create_community_resource, "name-2")
      conn = conn |> post(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end

    @tag :pending
    test "field missing"
  end
end
