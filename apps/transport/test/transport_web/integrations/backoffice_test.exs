defmodule TransportWeb.Integration.BackofficeTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  use TransportWeb.UserFacingCase
  import Plug.Test

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
