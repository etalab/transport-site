defmodule TransportWeb.Backoffice.GBFSLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase

  import Phoenix.LiveViewTest
  @endpoint TransportWeb.Endpoint

  @url "/backoffice/gbfs"

  setup do
    {:ok, conn: build_conn()}
  end

  test "requires login", %{conn: conn} do
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  # NOTE: this fakes previous proxy requests, without having to
  # setup a complete scenario, to prepare the data for the test below
  def add_events(network_name) do
    GBFS.Telemetry.trace_request(network_name, :external)
    GBFS.Telemetry.trace_request(network_name, :external)
    GBFS.Telemetry.trace_request(network_name, :internal)
    # events are async, so we wait a bit for now (not ideal)
    :timer.sleep(25)
  end

  test "disconnected and connected mount refresh stats", %{conn: conn} do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    network_name = "slug"
    add_events(network_name)

    conn = setup_admin_in_session(conn)
    conn = get(conn, @url)

    response = html_response(conn, 200)
    assert response =~ "Statistiques des requêtes GBFS"

    assert %{
             "Réseau" => ^network_name,
             "Req cache 7j" => "1",
             "Req ext 7j" => "2",
             "Req tot 7j" => "3"
           } = extract_data_from_html(response)

    {:ok, view, _html} = live(conn)

    add_events(network_name)

    send(view.pid, :update_data)

    assert %{
             "Réseau" => ^network_name,
             "Req cache 7j" => "2",
             "Req ext 7j" => "4",
             "Req tot 7j" => "6"
           } = extract_data_from_html(render(view))
  end
end
