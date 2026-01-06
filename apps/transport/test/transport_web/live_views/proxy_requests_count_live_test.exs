defmodule Transport.TransportWeb.ProxyRequestsCountLiveTest do
  use TransportWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import DB.Factory
  import Transport.Telemetry, only: [truncate_datetime_to_hour: 1]

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "renders the expected counts", %{conn: conn} do
    today = truncate_datetime_to_hour(DateTime.utc_now())
    yesterday = truncate_datetime_to_hour(DateTime.add(DateTime.utc_now(), -1, :day))
    two_months_ago = truncate_datetime_to_hour(DateTime.add(DateTime.utc_now(), -60, :day))

    insert(:metrics, target: "foo", event: "proxy:request:internal", count: 1, period: today)
    insert(:metrics, target: "foo", event: "proxy:request:external", count: 3, period: today)
    insert(:metrics, target: "bar", event: "gbfs:request:external", count: 2, period: yesterday)
    insert(:metrics, target: "bar", event: "gbfs:request:internal", count: 2, period: yesterday)
    insert(:metrics, target: "bar", event: "proxy:request:external", count: 200, period: two_months_ago)
    insert(:metrics, target: "bar", event: "proxy:request:internal", count: 200, period: two_months_ago)

    {:ok, view, _html} =
      conn
      |> Phoenix.ConnTest.init_test_session(%{"locale" => "fr"})
      |> live_isolated(TransportWeb.ProxyRequestsCountLive)

    assert %{socket: %Phoenix.LiveView.Socket{assigns: %{data: %{"external" => 5, "internal" => 3}}}} =
             :sys.get_state(view.pid)

    assert render(view) =~ ~s(<div class="proxy-external-requests">\n    5\n  </div>)
    assert render(view) =~ ~s(par un facteur de 1,7 sur cette période.)

    insert(:metrics, target: "baz", event: "proxy:request:external", count: 10, period: today)
    send(view.pid, :update_data)

    assert %{socket: %Phoenix.LiveView.Socket{assigns: %{data: %{"external" => 15, "internal" => 3}}}} =
             :sys.get_state(view.pid)

    assert render(view) =~ ~s(<div class="proxy-external-requests">\n    15\n  </div>)
    assert render(view) =~ ~s(par un facteur de 5 sur cette période.)
  end
end
