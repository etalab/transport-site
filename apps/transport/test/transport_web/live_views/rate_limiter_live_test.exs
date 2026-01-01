defmodule TransportWeb.Backoffice.RateLimiterLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import Phoenix.LiveViewTest
  import TransportWeb.ConnCase, only: [setup_admin_in_session: 1]

  @endpoint TransportWeb.Endpoint
  @url "/backoffice/rate_limiter"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    {:ok, conn: build_conn()}
  end

  test "requires login", %{conn: conn} do
    conn
    |> get(@url)
    |> html_response(302)
  end

  test "page can load", %{conn: conn} do
    conn
    |> setup_admin_in_session()
    |> get(@url)
    |> html_response(200)
  end

  test "ips_in_jail" do
    assert [] == PhoenixDDoS.Jail.ips_in_jail()
    PhoenixDDoS.Jail.send(~c"108.128.238.17", {nil, %{jail_time: {1, :hour}}})
    assert ["108.128.238.17"] == PhoenixDDoS.Jail.ips_in_jail()
  end

  test "bail out IP", %{conn: conn} do
    ip = "108.128.238.17"
    ip |> to_charlist() |> PhoenixDDoS.Jail.send({nil, %{jail_time: {1, :hour}}})
    {:ok, view, html} = conn |> setup_admin_in_session() |> live(@url)
    assert [ip] == PhoenixDDoS.Jail.ips_in_jail()

    assert html =~ ip

    assert view
           |> element("button", "Retirer de la jail")
           |> render_click()

    assert [] == PhoenixDDoS.Jail.ips_in_jail()

    send(view.pid, :update_data)

    refute render(view) =~ ip
  end
end
