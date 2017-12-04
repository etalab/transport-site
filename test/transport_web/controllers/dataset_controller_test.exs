defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  use Phoenix.ConnTest
  import Plug.Test
  alias Transport.Datagouvfr.Authentication

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données valides disponibles"
  end

  describe "POST /user/organizations/:organization/datasets/_create" do
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
  end

  describe "PATCH /user/datasets/:slug/improve" do
    test "logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(
          current_user: %{},
          client: Authentication.client("secret")
        )

      file = %Plug.Upload{
        path: "test/fixture/files/gtfs.zip",
        filename: "gtfs.zip"
      }

      params = %{
        "slug" => "hola",
        "dataset" => %{
          "dataset_id" => "5a0b1b240b5b39318769c3b1",
          "file" => file
        }
      }

      path = dataset_path(conn, :improve, params["slug"])
      conn = use_cassette "dataset/upload-dataset-file-0" do
        patch(conn, path, params)
      end

      assert redirected_to(conn, 302) == dataset_path(conn, :details, params["slug"])
    end
  end
end
