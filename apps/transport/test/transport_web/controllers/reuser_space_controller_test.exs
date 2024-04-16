defmodule TransportWeb.ReuserSpaceControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "espace_reutilisateur", %{conn: conn} do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    content =
      conn
      |> Plug.Test.init_test_session(%{current_user: %{"id" => contact.datagouv_user_id}})
      |> get(reuser_space_path(conn, :espace_reutilisateur))
      |> html_response(200)

    # Feedback form is displayed
    refute content |> Floki.parse_document!() |> Floki.find("form.feedback-form") |> Enum.empty?()
  end
end
