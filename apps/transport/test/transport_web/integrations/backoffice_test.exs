defmodule TransportWeb.Integration.BackofficeTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  use TransportWeb.UserFacingCase
  import Plug.Test

  @tag :integration
  test "deny acces to backoffice if not logged" do
    @endpoint
    |> backoffice_page_url(:index)
    |> navigate_to

    :class
    |> find_element("notification")
    |> visible_text
    |> Kernel.==("Vous devez être préalablement connecté·e.")
    |> assert
  end

  @tag :integration
  test "check that you belong to the right organization", %{conn: conn} do
    conn
    |> init_test_session(%{current_user: %{"organizations" => [%{"slug" => "pouet pouet"}]}})
    |> get("/backoffice")
    |> get_flash(:error)
    |> Kernel.=~("You need to be a member of the transport.data.gouv.fr team.")
    |> assert
  end

  @tag :integration
  test "show add new dataset form", %{conn: conn} do
    conn
    |> init_test_session(%{
      current_user: %{"organizations" => [%{"slug" => "blurp"}, %{"slug" => "equipe-transport-data-gouv-fr"}]}
    })
    |> get("/backoffice")
    |> html_response(200)
  end
end
