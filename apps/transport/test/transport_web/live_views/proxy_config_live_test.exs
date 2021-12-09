defmodule TransportWeb.Backoffice.ProxyConfigLiveTest do
  use ExUnit.Case, async: false
  use TransportWeb.LiveCase

  import Phoenix.LiveViewTest
  @endpoint TransportWeb.Endpoint
  import Mox

  @url "/backoffice/proxy-config"

  setup do
    {:ok, conn: build_conn()}
  end

  def setup_proxy_config(slug) do
    config = %{
      slug => %Unlock.Config.Item{
        identifier: slug,
        target_url: "http://localhost/some-remote-resource",
        ttl: 10
      }
    }

    Unlock.Config.Fetcher.Mock
    |> stub(:fetch_config!, fn -> config end)
  end

  test "requires login", %{conn: conn} do
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  def add_events(item_id) do
    target = "proxy:#{item_id}"
    Transport.Telemetry.count_event(target, event_name(:external))
    Transport.Telemetry.count_event(target, event_name(:external))
    Transport.Telemetry.count_event(target, event_name(:internal))
  end

  defp event_name(type) do
    type |> Transport.Telemetry.proxy_request_event_name()
  end

  test "disconnected and connected mount refresh stats", %{conn: conn} do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    item_id = "slug"
    setup_proxy_config(item_id)

    add_events(item_id)

    conn = setup_admin_in_session(conn)
    conn = get(conn, @url)

    response = html_response(conn, 200)
    assert response =~ "Configuration du Proxy"

    assert %{
             "Identifiant" => "slug",
             "Req ext 7j" => "2",
             "Req int 7j" => "1"
           } = extract_data_from_html(response)

    {:ok, view, _html} = live(conn)

    add_events(item_id)

    send(view.pid, :update_data)

    assert %{
             "Identifiant" => "slug",
             "Req ext 7j" => "4",
             "Req int 7j" => "2"
           } = extract_data_from_html(render(view))
  end
end
