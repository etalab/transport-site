defmodule TransportWeb.Backoffice.GBFSLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase

  import Phoenix.LiveViewTest
  @endpoint TransportWeb.Endpoint

  @url "/backoffice/gbfs"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.Metrics)
    {:ok, conn: build_conn()}
  end

  test "requires login", %{conn: conn} do
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  def add_events(network_name) do
    target = "gbfs:#{network_name}"
    Transport.Telemetry.count_event(target, event_name(:external))
    Transport.Telemetry.count_event(target, event_name(:external))
    Transport.Telemetry.count_event(target, event_name(:internal))
  end

  defp event_name(type) do
    type |> Transport.Telemetry.gbfs_request_event_name()
  end

  test "disconnected and connected mount refresh stats", %{conn: conn} do
    network_name = "slug"
    add_events(network_name)

    conn = setup_admin_in_session(conn)
    conn = get(conn, @url)

    response = html_response(conn, 200)
    assert response =~ "Statistiques des requêtes GBFS"

    assert [
             %{
               "Réseau" => ^network_name,
               "Req int 7j" => "1",
               "Req ext 7j" => "2"
             }
           ] = extract_data_from_html(response)

    {:ok, view, _html} = live(conn)

    add_events(network_name)

    send(view.pid, :update_data)

    assert [
             %{
               "Réseau" => ^network_name,
               "Req int 7j" => "2",
               "Req ext 7j" => "4"
             }
           ] = extract_data_from_html(render(view))
  end
end
