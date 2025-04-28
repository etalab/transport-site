defmodule TransportWeb.ExploreControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    insert_bnlc_dataset()
    insert_parcs_relais_dataset()
    insert_zfe_dataset()
    insert_irve_dataset()

    :ok
  end

  test "GET /explore", %{conn: conn} do
    conn = conn |> get(~p"/explore")
    html = html_response(conn, 200)
    assert html =~ "Carte d&#39;exploration des données"
    assert 6 == (html |> String.split("checked") |> Enum.count()) - 1

    conn = conn |> get(~p"/explore?zfe=yes")
    html = html_response(conn, 200)
    assert 1 == (html |> String.split("checked") |> Enum.count()) - 1
  end

  test "GET /explore/vehicle-positions", %{conn: conn} do
    redirect_path =
      conn
      |> get(~p"/explore/vehicle-positions")
      |> redirected_to(302)

    assert redirect_path == "/explore"
  end

  test "GET /explore/gtfs-stops", %{conn: conn} do
    conn = conn |> get(~p"/explore/gtfs-stops")
    html = html_response(conn, 200)
    doc = Floki.parse_document!(html)

    [{"title", _, [title]}] = Floki.find(doc, "title")

    assert title == "Carte consolidée des arrêts GTFS (beta)"
    assert html =~ "<h2>Carte consolidée des arrêts GTFS (beta)</h2>"
  end
end
