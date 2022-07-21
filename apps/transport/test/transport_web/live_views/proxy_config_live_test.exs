defmodule TransportWeb.Backoffice.ProxyConfigLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase

  import Phoenix.LiveViewTest
  @endpoint TransportWeb.Endpoint
  import Mox

  @url "/backoffice/proxy-config"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.Metrics)
    {:ok, conn: build_conn()}
  end

  setup :verify_on_exit!

  def setup_proxy_config(slug, siri_slug) do
    config = %{
      slug => %Unlock.Config.Item.GTFS.RT{
        identifier: slug,
        target_url: "http://localhost/some-remote-resource",
        ttl: 10
      },
      siri_slug => %Unlock.Config.Item.SIRI{
        identifier: siri_slug,
        target_url: "http://localhost/some-siri-resource",
        requestor_ref: "secret"
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
    item_id = "gtfs-rt-slug"
    siri_item_id = "siri-slug"
    setup_proxy_config(item_id, siri_item_id)

    add_events(item_id)

    conn = setup_admin_in_session(conn)
    conn = get(conn, @url)

    response = html_response(conn, 200)
    assert response =~ "Configuration du Proxy"

    assert [first_item, second_item] = extract_data_from_html(response)

    assert %{
             "Identifiant" => "siri-slug",
             "Req ext 7j" => "0",
             "Req int 7j" => "0"
           } = second_item

    assert %{
             "Identifiant" => "gtfs-rt-slug",
             "Req ext 7j" => "2",
             "Req int 7j" => "1"
           } = first_item

    {:ok, view, _html} = live(conn)

    add_events(item_id)

    send(view.pid, :update_data)

    [first_item, _second_item] = extract_data_from_html(render(view))

    assert %{
             "Identifiant" => "gtfs-rt-slug",
             "Req ext 7j" => "4",
             "Req int 7j" => "2"
           } = first_item
  end
end
