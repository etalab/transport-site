defmodule TransportWeb.ReuserSpaceControllerTest do
  use TransportWeb.ConnCase, async: true

  test "espace_reutilisateur", %{conn: conn} do
    assert conn |> get(reuser_space_path(conn, :espace_reutilisateur)) |> text_response(200)
  end
end
