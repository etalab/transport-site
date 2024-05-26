defmodule TransportWeb.ReuserSpaceControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  @home_url reuser_space_path(TransportWeb.Endpoint, :espace_reutilisateur)

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "espace_reutilisateur" do
    test "logged out", %{conn: conn} do
      conn = conn |> get(@home_url)
      assert redirected_to(conn, 302) == page_path(conn, :infos_reutilisateurs)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    end

    test "logged in", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      content =
        conn
        |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
        |> get(@home_url)
        |> html_response(200)

      # Feedback form is displayed
      refute content |> Floki.parse_document!() |> Floki.find("form.feedback-form") |> Enum.empty?()
    end
  end

  describe "datasets_edit" do
    test "logged out", %{conn: conn} do
      conn = conn |> get(reuser_space_path(conn, :datasets_edit, 42))
      assert redirected_to(conn, 302) == page_path(conn, :infos_reutilisateurs)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    end

    test "logged in", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      assert conn
             |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
             |> get(reuser_space_path(conn, :datasets_edit, 42))
             |> text_response(200) == "Coming later"
    end
  end
end
