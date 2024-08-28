defmodule TransportWeb.Plugs.PutLocaleTest do
  use TransportWeb.ConnCase, async: true
  doctest TransportWeb.Plugs.PutLocale, import: true

  @path page_path(TransportWeb.Endpoint, :missions)

  test "uses the locale query parameter", %{conn: conn} do
    conn = get(conn, @path)

    assert Plug.Conn.get_session(conn, :locale) == "fr"

    conn = get(conn, @path, locale: "en")
    assert Plug.Conn.get_session(conn, :locale) == "en"
  end

  test "uses the locale in the session", %{conn: conn} do
    conn = conn |> Plug.Test.init_test_session(%{locale: "en"}) |> get(@path)
    assert Plug.Conn.get_session(conn, :locale) == "en"
  end

  test "uses the accept-language header", %{conn: conn} do
    conn = conn |> Plug.Conn.put_req_header("accept-language", "en-CA;q=0.9, *;q=0.5") |> get(@path)

    assert Plug.Conn.get_session(conn, :locale) == "en"
  end

  test "400 if the locale is not supported", %{conn: conn} do
    assert conn |> get(@path, locale: "es") |> text_response(400) == "Locale is not supported."
  end

  test "locale is switched in Gettext", %{conn: conn} do
    TransportWeb.Plugs.PutLocale.supported_locales()
    |> Enum.each(fn locale ->
      html = conn |> get(@path, locale: locale) |> html_response(200)
      assert html |> Floki.parse_document!() |> Floki.attribute("html", "lang") == [locale]
    end)
  end
end
