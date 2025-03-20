defmodule TransportWeb.ReuseControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "index", %{conn: conn} do
    insert(:reuse, title: title = "Ma réutilisation")
    assert conn |> get(reuse_path(conn, :index)) |> html_response(200) =~ title
  end
end
