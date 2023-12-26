defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: []
  import DB.Factory
  import Plug.Test, only: [init_test_session: 2]
  import Mox

  setup :verify_on_exit!

  doctest TransportWeb.PageController

  test "GET /", %{conn: conn} do
    conn = conn |> get(page_path(conn, :index))
    html = html_response(conn, 200)
    assert html =~ "disponible, valoriser et améliorer"
  end

  test "GET / shows a contact button", %{conn: conn} do
    conn = conn |> get(page_path(conn, :index))

    [_element] =
      conn
      |> html_response(200)
      |> Floki.parse_document!()
      |> Floki.find(".mail__button .icon--envelope")
  end

  test "GET login page without a redirect_path", %{conn: conn} do
    conn |> get(page_path(conn, :login)) |> html_response(200)
  end

  test "I can see a log-in link on home", %{conn: conn} do
    # go to the home page
    conn = conn |> get("/")
    doc = html_response(conn, 200)
    html = doc |> Floki.parse_document!()

    # simulate click on login link
    [link] = Floki.find(html, ".navigation__link--login")
    [href] = Floki.attribute(link, "href")
    assert href == "/login/explanation?redirect_path=%2F"
    conn = conn |> get(href)

    # verify the content
    html = html_response(conn, 200)
    assert html =~ "disponible, valoriser et améliorer"

    # I have an explanation of what data.gouv.fr is
    assert html =~ "plateforme ouverte des données publiques françaises"

    # I have an explanation of what the relationship is between data.gouv.fr and Transport
    assert html =~ "transport.data.gouv.fr est un site affilié à data.gouv.fr"

    # I have an explanation of what's going to happen and what I'm I supposed to do
    assert html =~ "créer un compte ou vous identifier avec votre compte data.gouv.fr"
    assert html =~ "autoriser transport.data.gouv.fr à utiliser votre compte data.gouv.fr"

    # I can click somewhere to start the log in / sign up process
    assert html =~ "Se connecter"

    # I can click somewhere to ask for help
    assert html =~ "Nous contacter"
  end

  describe "GET /espace_producteur" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> get(page_path(conn, :espace_producteur))
      assert redirected_to(conn, 302) =~ "/login"
    end

    test "renders successfully and finds datasets using organization IDs", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id} = insert(:dataset, datagouv_title: datagouv_title = "Foobar")

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      conn =
        conn
        |> init_test_session(current_user: %{})
        |> get(page_path(conn, :espace_producteur))

      {:ok, doc} = conn |> html_response(200) |> Floki.parse_document()
      assert Floki.find(doc, ".message--error") == []

      assert doc |> Floki.find(".dataset-item h5") |> Enum.map(&(&1 |> Floki.text() |> String.trim())) == [
               datagouv_title
             ]
    end

    test "with an OAuth2 error", %{conn: conn} do
      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:error, "its broken"} end)

      conn =
        conn
        |> init_test_session(current_user: %{})
        |> get(page_path(conn, :espace_producteur))

      {:ok, doc} = conn |> html_response(200) |> Floki.parse_document()
      assert doc |> Floki.find(".dataset-item") |> length == 0

      assert doc |> Floki.find(".message--error") |> Floki.text() ==
               "Une erreur a eu lieu lors de la récupération de vos ressources"
    end
  end

  test "GET /producteurs for non-authenticated users", %{conn: conn} do
    conn = conn |> get(page_path(conn, :infos_producteurs))
    body = html_response(conn, 200)
    assert body =~ "transport.data.gouv.fr vous aide à publier vos données"

    {:ok, doc} = Floki.parse_document(body)
    [item] = doc |> Floki.find(".panel-producteurs a.button")

    # behavior expected for non-authenticated users
    assert Floki.attribute(item, "href") == ["/login/explanation?redirect_path=%2Finfos_producteurs"]
    assert item |> Floki.text() =~ "Identifiez-vous"
  end

  test "404 page", %{conn: conn} do
    conn = conn |> get("/this-page-does-not-exist")
    html = html_response(conn, 404)
    assert html =~ "Page non disponible"
  end

  test "security.txt page", %{conn: conn} do
    conn |> get("/.well-known/security.txt") |> text_response(200)
  end

  describe "robots.txt" do
    test "it works", %{conn: conn} do
      refute conn |> get("/robots.txt") |> text_response(200) =~ ~r(Disallow: \/$)
    end

    test "it works in staging with a different content", %{conn: conn} do
      AppConfigHelper.change_app_config_temporarily(:transport, :app_env, :staging)
      assert conn |> get("/robots.txt") |> text_response(200) =~ ~r(Disallow: \/$)
    end
  end

  test "accessibility page", %{conn: conn} do
    conn |> get(page_path(conn, :accessibility)) |> html_response(200)
  end

  test "missions page", %{conn: conn} do
    conn |> get(page_path(conn, :missions)) |> html_response(200)
  end

  test "climate and resilience bill page", %{conn: conn} do
    conn = conn |> get(page_path(conn, :loi_climat_resilience)) |> html_response(200)
    assert conn |> Floki.parse_document!() |> Floki.find("title") |> Floki.text() =~ ~r"^Loi climat et résilience"
  end

  test "budget page", %{conn: conn} do
    conn |> get("/budget") |> redirected_to(302) =~ "https://doc.transport.data.gouv.fr"
  end

  test "humans txt", %{conn: conn} do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://beta.gouv.fr/api/v2.5/authors.json" ->
      body = [
        %{"id" => "foo", "fullname" => "Foo"},
        %{"id" => "bar", "fullname" => "Bar"},
        %{"id" => "baz", "fullname" => "Baz"}
      ]

      %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}
    end)

    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://beta.gouv.fr/api/v2.5/startups_details.json" ->
      body = %{
        "transport" => %{
          "active_members" => ["foo"],
          "previous_members" => ["bar"],
          "expired_members" => ["baz", "nope"]
        }
      }

      %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}
    end)

    content = conn |> get(page_path(conn, :humans_txt)) |> text_response(200)
    assert content == "# Membres actuels\nFoo\n\n# Anciens membres\nBar\nBaz"
  end

  test "menu has a link to producer space when the user is a producer", %{conn: conn} do
    espace_producteur_path = page_path(conn, :espace_producteur, utm_source: "menu_dropdown")

    has_menu_item? = fn %Plug.Conn{} = conn ->
      conn
      |> get(page_path(conn, :index))
      |> html_response(200)
      |> Floki.parse_document!()
      |> Floki.find("nav .dropdown-content a")
      |> Enum.any?(&(&1 == {"a", [{"href", espace_producteur_path}], ["Espace producteur"]}))
    end

    refute conn
           |> init_test_session(current_user: %{"is_producer" => false})
           |> has_menu_item?.()

    assert conn
           |> init_test_session(current_user: %{"is_producer" => true})
           |> has_menu_item?.()
  end
end
