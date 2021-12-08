defmodule TransportWeb.Backoffice.ProxyConfigLiveTest do
  use TransportWeb.LiveCase

  import Phoenix.LiveViewTest
  @endpoint TransportWeb.Endpoint
  import Mox

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
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
    conn = get(conn, "/backoffice/proxy-config")
    assert html_response(conn, 302)
  end

  # NOTE: this fakes previous proxy requests, without having to
  # setup a complete scenario, to prepare the data for the test below
  def add_events(item_id) do
    Unlock.Controller.Telemetry.trace_request(item_id, :external)
    Unlock.Controller.Telemetry.trace_request(item_id, :external)
    Unlock.Controller.Telemetry.trace_request(item_id, :internal)
    # events are async, so we wait a bit for now (not ideal)
    :timer.sleep(25)
  end

  test "disconnected and connected mount refresh stats", %{conn: conn} do
    item_id = "slug"
    setup_proxy_config(item_id)

    add_events(item_id)

    conn = setup_admin_in_session(conn)
    conn = get(conn, "/backoffice/proxy-config")

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
