defmodule TransportWeb.Backoffice.CacheLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import TransportWeb.ConnCase, only: [setup_admin_in_session: 1]
  import Transport.Application, only: [cache_name: 0]
  import Phoenix.LiveViewTest

  @endpoint TransportWeb.Endpoint
  @url "/backoffice/cache"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> Cachex.clear(Transport.Application.cache_name()) end)
    {:ok, conn: build_conn()}
  end

  test "requires login", %{conn: conn} do
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  test "displays the expected data", %{conn: conn} do
    conn = setup_admin_in_session(conn)
    conn = get(conn, @url)

    response = html_response(conn, 200)
    assert response =~ "Debug du cache de l'application transport"

    assert response =~ "Nombre de clés : 0"
    assert response =~ "Nombre de clés expirées : 0"
    assert [] == extract_data_from_html(response)

    {:ok, view, _html} = live(conn)

    Cachex.put(cache_name(), "foo", 42)
    Cachex.put(cache_name(), "bar", "value", expire: :timer.seconds(10))

    send(view.pid, :update_data)

    assert render(view) =~ "Nombre de clés : 2"
    assert render(view) =~ "Nombre de clés expirées : 0"

    assert [
             %{"Clé" => "bar", "TTL" => "dans 10 secondes"},
             %{"Clé" => "foo", "TTL" => "Pas de TTL"}
           ] = extract_data_from_html(render(view))
  end
end
