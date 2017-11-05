defmodule TransportWeb.DatasetControllerTest do
  use TransportWeb.ConnCase

  doctest TransportWeb.DatasetController

  test "GET /", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    assert html_response(conn, 200) =~ "Jeux de données disponibles"
  end
end
