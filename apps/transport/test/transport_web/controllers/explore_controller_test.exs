defmodule TransportWeb.ExploreControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    insert(:dataset, %{
      type: "private-parking",
      custom_title: "Base nationale des parcs relais",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)
    })

    :ok
  end

  test "GET /explore", %{conn: conn} do
    conn = conn |> get("/explore")
    html = html_response(conn, 200)
    assert html =~ "Exploration"
  end

  test "GET /explore/vehicle-positions", %{conn: conn} do
    conn =
      conn
      |> get("/explore/vehicle-positions")

    assert redirected_to(conn, 302) == "/explore"
  end
end
