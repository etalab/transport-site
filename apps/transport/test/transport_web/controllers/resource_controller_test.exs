defmodule TransportWeb.ResourceControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.DatabaseCase, cleanup: [:datasets], async: false
  import Plug.Test

  test "I can see my datasets", %{conn: conn} do
    conn
    |> init_test_session(%{current_user: %{"organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]}})
    |> get("/resources/update/datasets")
    |> html_response(200)
  end
end
