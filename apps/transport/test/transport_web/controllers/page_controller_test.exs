defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Plug.Test, only: [init_test_session: 2]
  import Mox

  setup :verify_on_exit!

  doctest TransportWeb.PageController

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

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
    conn = conn |> get(~p"/")
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

  describe "infos_producteurs" do
    test "for logged-out users", %{conn: conn} do
      conn = conn |> get(page_path(conn, :infos_producteurs))
      body = html_response(conn, 200)
      assert body =~ "transport.data.gouv.fr vous aide à publier vos données"

      {:ok, doc} = Floki.parse_document(body)
      [item] = doc |> Floki.find(".panel-producteurs a.button")

      assert Floki.attribute(item, "href") == ["/login/explanation?redirect_path=%2Fespace_producteur"]
      assert item |> Floki.text() =~ "Identifiez-vous"
    end

    test "for logged-in users", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
      Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> [] end)

      conn =
        conn
        |> init_test_session(current_user: %{"is_producer" => true, "id" => contact.datagouv_user_id})
        |> get(page_path(conn, :infos_producteurs))

      body = html_response(conn, 200)
      assert body =~ "transport.data.gouv.fr vous aide à publier vos données"

      {:ok, doc} = Floki.parse_document(body)
      [item] = doc |> Floki.find(".panel-producteurs a.button")

      assert Floki.attribute(item, "href") == ["/espace_producteur?utm_campaign=producer_infos_page"]
      assert item |> Floki.text() =~ "Accédez à votre espace producteur"
    end
  end

  describe "infos_reutilisateurs" do
    test "for logged-out users", %{conn: conn} do
      conn = conn |> get(page_path(conn, :infos_reutilisateurs))
      body = html_response(conn, 200)
      assert body =~ "transport.data.gouv.fr vous aide à suivre les données que vous réutilisez"

      {:ok, doc} = Floki.parse_document(body)
      [item] = doc |> Floki.find(".panel-producteurs a.button")

      assert Floki.attribute(item, "href") == ["/login/explanation?redirect_path=%2Fespace_reutilisateur"]
      assert item |> Floki.text() =~ "Identifiez-vous"
    end

    test "for logged-in users", %{conn: conn} do
      contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

      conn =
        conn
        |> init_test_session(current_user: %{"is_producer" => false, "id" => contact.datagouv_user_id})
        |> get(page_path(conn, :infos_reutilisateurs))

      body = html_response(conn, 200)
      assert body =~ "transport.data.gouv.fr vous aide à suivre les données que vous réutilisez"

      {:ok, doc} = Floki.parse_document(body)
      [item] = doc |> Floki.find(".panel-producteurs a.button")

      assert Floki.attribute(item, "href") == ["/espace_reutilisateur?utm_campaign=reuser_infos_page"]
      assert item |> Floki.text() =~ "Accédez à votre espace réutilisateur"
    end
  end

  test "404 page", %{conn: conn} do
    conn = conn |> get("/this-page-does-not-exist")
    html = html_response(conn, 404)
    assert html =~ "Page non disponible"
  end

  test "security.txt page", %{conn: conn} do
    conn |> get(~p"/.well-known/security.txt") |> text_response(200)
  end

  test "nouveautés", %{conn: conn} do
    content = conn |> get(~p"/nouveautes") |> html_response(200)

    doc = content |> Floki.parse_document!()

    assert doc |> Floki.find(".side-pane__dropdown.unfolded") |> Enum.count() == 1
    assert doc |> Floki.find(".side-pane__dropdown.folded") |> Enum.count() >= 1

    tags = doc |> Floki.find("h2, h3") |> Floki.text(sep: "|") |> String.replace("#| \n", "") |> String.split("|")

    assert sublist?(tags, [
             "Décembre 2025",
             "⚡️ IRVE",
             "🚀 Espace Producteur & Expérience Utilisateur",
             "🔍 Recherche",
             "🛠 Validation & Qualité des Données",
             "🔌 Proxy & Flux Temps Réel",
             "📧 Notifications & Backoffice",
             "⚙️ Technique & Infrastructure"
           ])
  end

  describe "robots.txt" do
    test "200 response, doesn't disallow indexing everything and includes sitemap", %{conn: conn} do
      content = conn |> get(~p"/robots.txt") |> text_response(200)
      refute content =~ ~r(Disallow: \/\n)
      assert content =~ "Sitemap: http://127.0.0.1:5100/sitemap.txt"
    end

    test "disallow indexing everything in staging" do
      assert TransportWeb.PageController.robots_txt_content(:staging) =~ ~r(Disallow: \/$)
      refute TransportWeb.PageController.robots_txt_content(:prod) =~ ~r(Disallow: \/$)
    end
  end

  test "accessibility page", %{conn: conn} do
    conn |> get(page_path(conn, :accessibility)) |> html_response(200)
  end

  test "missions page", %{conn: conn} do
    conn |> get(page_path(conn, :missions)) |> html_response(200)
  end

  test "sitemap page", %{conn: conn} do
    conn |> get(page_path(conn, :sitemap_txt)) |> text_response(200)
  end

  test "budget page", %{conn: conn} do
    conn |> get(~p"/budget") |> redirected_to(302) =~ "https://doc.transport.data.gouv.fr"
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
          "previous_members" => ["bar", "baz"],
          "expired_members" => ["baz", "nope"]
        }
      }

      %HTTPoison.Response{status_code: 200, body: Jason.encode!(body)}
    end)

    content = conn |> get(page_path(conn, :humans_txt)) |> text_response(200)
    assert content == "# Membres actuels\nFoo\n\n# Anciens membres\nBar\nBaz"
  end

  test "menu has a link to producer space when the user is a producer", %{conn: conn} do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    has_menu_item? = fn %Plug.Conn{} = conn ->
      not (conn
           |> get(page_path(conn, :index))
           |> html_response(200)
           |> Floki.parse_document!()
           |> Floki.find(~s|nav .dropdown-content a[data-link-name="producer-space"]|)
           |> Enum.empty?())
    end

    refute conn
           |> init_test_session(current_user: %{"is_producer" => false, "id" => contact.datagouv_user_id})
           |> has_menu_item?.()

    Datagouvfr.Client.User.Mock |> expect(:me, fn _conn -> [] end)

    assert conn
           |> init_test_session(current_user: %{"is_producer" => true, "id" => contact.datagouv_user_id})
           |> has_menu_item?.()
  end

  test "menu has notification count if producer has issues to tackle", %{conn: conn} do
    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})
    %DB.Dataset{organization_id: organization_id, datagouv_id: dataset_datagouv_id} = dataset = insert(:dataset)
    insert(:resource, dataset: dataset, is_available: false)

    Datagouvfr.Client.User.Mock
    |> expect(:me, fn _conn -> {:ok, %{"organizations" => [%{"id" => dataset.organization_id}]}} end)

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, fn ^organization_id, [restrict_fields: true] ->
      {:ok, %{"members" => []}}
    end)

    Datagouvfr.Client.Discussions.Mock |> expect(:get, fn ^dataset_datagouv_id -> [] end)

    doc =
      conn
      |> init_test_session(current_user: %{"is_producer" => true, "id" => contact.datagouv_user_id})
      |> get(page_path(conn, :index))
      |> html_response(200)
      |> Floki.parse_document!()

    assert doc |> Floki.find(".notification_badge") == [
             {"span", [{"class", "notification_badge"}, {"aria-label", "1 notification"}], ["\n  1\n"]},
             {"span", [{"class", "notification_badge static"}, {"aria-label", "1 notification"}], ["\n  1\n"]}
           ]

    assert doc
           |> Floki.find(~s|nav .dropdown-content a[data-link-name="producer-space"]|)
           |> Floki.text()
           |> String.trim()
           |> String.replace(~r/(\s)+/, " ") ==
             "Espace producteur 1"
  end

  def sublist?(list, sublist) do
    list
    |> Enum.chunk_every(length(sublist), 1, :discard)
    |> Enum.member?(sublist)
  end
end
