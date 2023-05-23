defmodule TransportWeb.ExploreControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    pan_org = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    insert(:dataset, %{type: "carpooling-areas", organization: pan_org})

    insert(:dataset, %{type: "private-parking", custom_title: "Base nationale des parcs relais", organization: pan_org})

    insert(:dataset, %{
      type: "low-emission-zones",
      custom_title: "Base Nationale des Zones à Faibles Émissions (BNZFE)",
      organization: pan_org
    })

    :ok
  end

  test "GET /explore", %{conn: conn} do
    conn = conn |> get("/explore")
    html = html_response(conn, 200)
    assert html =~ "Exploration"
  end

  test "GET /explore/vehicle-positions", %{conn: conn} do
    redirect_path =
      conn
      |> get("/explore/vehicle-positions")
      |> redirected_to(302)

    assert redirect_path == "/explore"
  end

  test "GET /explore/gtfs-stops", %{conn: conn} do
    conn = conn |> get("/explore/gtfs-stops")
    html = html_response(conn, 200)
    doc = Floki.parse_document!(html)

    [{"title", _, [title]}] = Floki.find(doc, "title")
    [{"h2", _, [h2]}] = Floki.find(doc, "h2")

    assert title == "Carte consolidée des arrêts GTFS (beta)"
    assert h2 == "Carte consolidée des arrêts GTFS (beta)"
  end
end
