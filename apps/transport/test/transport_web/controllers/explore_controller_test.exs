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

    insert(:dataset, %{
      type: "charging-stations",
      custom_title: "Infrastructures de Recharge pour Véhicules Électriques - IRVE",
      organization: "data.gouv.fr",
      organization_id: "646b7187b50b2a93b1ae3d45"
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

    assert title == "Carte consolidée des arrêts GTFS (beta)"
    assert html =~ "<h2>Carte consolidée des arrêts GTFS (beta)</h2>"
  end

  test "GET /explore/gtfs-stops-data without parameters", %{conn: conn} do
    conn = conn |> get("/explore/gtfs-stops-data")
    json = json_response(conn, 422)
    assert json["error"] == "incorrect parameters"
  end

  test "GET /explore/gtfs-stops-data with parameters", %{conn: conn} do
    conn =
      conn
      |> get("/explore/gtfs-stops-data", %{
        "south" => "48.8",
        "east" => "2.4",
        "west" => "2.2",
        "north" => "48.9",
        "width_pixels" => "1000",
        "height_pixels" => "1000",
        "zoom_level" => "12"
      })

    json = json_response(conn, 200)
    assert json["data"]["type"] == "FeatureCollection"
  end
end
