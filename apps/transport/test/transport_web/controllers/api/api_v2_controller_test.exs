defmodule TransportWeb.API.V2.ControllerTest do
  use TransportWeb.ConnCase, async: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "resources", %{conn: conn} do
    conn = conn |> get(~p"/api/v2/resources")
    json = json_response(conn, 200)

    assert json == %{"hello" => "world"}
  end
end
