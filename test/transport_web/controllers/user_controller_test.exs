defmodule TransportWeb.UserControllerTest do
  use TransportWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  import Plug.Test
  alias Transport.Datagouvfr.Authentication
  import TransportWeb.Gettext

  doctest TransportWeb.UserController

  describe "GET /user/organizations" do
    test "logged in", %{conn: conn} do
      use_cassette "user/organizations-0" do
        conn = conn
        |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
        |> get(user_path(conn, :organizations))

        assert html_response(conn, 200)
      end
    end

    test "not logged in", %{conn: conn} do
      path = user_path(conn, :organizations)
      conn = conn |> get(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end

    test "user with no organisation", %{conn: conn} do
      use_cassette "user/user-without-organization-3" do
        conn = conn
        |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
        |> get(user_path(conn, :organizations))

        assert redirected_to(conn, 302) == user_path(conn, :organization_form)
      end
    end
  end

  describe "GET /user/organizations/form" do
    test "logged in", %{conn: conn} do
      use_cassette "user/organizations-0" do
        conn = conn
        |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
        |> get(user_path(conn, :organization_form))

        assert html_response(conn, 200) =~ "<form"
      end
    end

    test "not logged in", %{conn: conn} do
      path = user_path(conn, :organization_form)
      conn = conn |> get(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end
  end

  describe "GET /user/organizations/mon-aot/datasets/" do
    test "logged in", %{conn: conn} do
      conn = use_cassette "session/create-2" do
        conn |> get(session_path(conn, :create, %{"code" => "loxDqYJwrzwdFwzkfIH4gC4JaVy2qj"}))
      end

      conn = assign(conn, :client, Authentication.client())
      conn = use_cassette "user/organization-datasets-1" do
        conn |> get(user_path(conn, :organization_datasets, "mon-aot"))
      end

      assert html_response(conn, 200) =~ "Mon AOT"
      assert html_response(conn, 200) =~ "GTFS"
    end

    test "not logged in", %{conn: conn} do
      path = user_path(conn, :organization_datasets, "mon-aot")
      conn = conn |> get(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end
  end

  describe "GET /user/datasets/le-plan-de-transport/_add" do
    test "logged in", %{conn: conn} do
      conn = use_cassette "session/create-2" do
        conn |> get(session_path(conn, :create, %{"code" => "secret"}))
      end

      conn = use_cassette "user/dataset-add-2" do
        conn |> get(user_path(conn, :add_badge_dataset, "le-plan-de-transport"))
      end

      assert html_response(conn, 200) =~ "vérifié"
    end

    test "not logged in", %{conn: conn} do
      path = user_path(conn, :add_badge_dataset, "le-plan-de-transport")
      conn = conn |> get(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end
  end

  describe "POST /user/organizations/_create" do
    test "logged in", %{conn: conn} do
      use_cassette "user/organization-create-4" do
        conn = conn
        |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
        |> post(user_path(conn, :organization_create, name: "name", description: "description"))
        assert redirected_to(conn, 302) == user_path(conn, :organization_datasets, "name")
      end
    end

    test "not logged in", %{conn: conn} do
      path = user_path(conn, :organization_create, %{"name" => "", "description" => ""})
      conn = conn |> post(path)
      assert redirected_to(conn, 302) == page_path(conn, :login, redirect_path: path)
    end

    test "name field missing", %{conn: conn} do
      conn = conn
      |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
      |> post(user_path(conn, :organization_create, description: "description"))
      assert redirected_to(conn, 302) == user_path(conn, :organization_form)

      conn = conn
      |> get(user_path(conn, :organization_form))
      assert html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation name")
      assert false == (html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation description"))
    end

    test "description field missing", %{conn: conn} do
      conn =
      conn
      |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
      |> post(user_path(conn, :organization_create, name: "name"))
      assert redirected_to(conn, 302) == user_path(conn, :organization_form)

      conn =
      conn
      |> get(user_path(conn, :organization_form))
      assert false == (html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation name"))
      assert html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation description")
    end

    test "name field is empty", %{conn: conn} do
      conn =
      conn
      |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
      |> post(user_path(conn, :organization_create, name: "", description: "description"))
      assert redirected_to(conn, 302) == user_path(conn, :organization_form)

      conn =
      conn
      |> get(user_path(conn, :organization_form))
      assert html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation name")
      assert false == (html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation description"))
    end

    test "description field is empty", %{conn: conn} do
      conn =
      conn
      |> init_test_session(current_user: %{}, client: Authentication.client("secret"))
      |> post(user_path(conn, :organization_create, name: "name", description: ""))
      assert redirected_to(conn, 302) == user_path(conn, :organization_form)

      conn =
      conn
      |> get(user_path(conn, :organization_form))
      assert false == (html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation name"))
      assert html_response(conn, 200) =~ dgettext("user", "You need to provide an organisation description")
    end

  end
end
