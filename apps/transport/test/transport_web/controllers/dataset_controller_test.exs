defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase
  use TransportWeb.DatabaseCase, cleanup: [:datasets]

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données disponibles"
  end
end
