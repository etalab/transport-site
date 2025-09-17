defmodule TransportWeb.PageControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Plug.Test, only: [init_test_session: 2]
  import Mox

  setup :verify_on_exit!

  doctest TransportWeb.PageController

  setup do
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

  describe "GET /espace_producteur" do
    test "requires authentication", %{conn: conn} do
      conn = conn |> get(page_path(conn, :espace_producteur))
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
      assert redirected_to(conn, 302) == page_path(conn, :infos_producteurs)
    end

    test "renders successfully and finds datasets using organization IDs", %{conn: conn} do
      %DB.Dataset{organization_id: organization_id} =
        dataset = insert(:dataset, datagouv_title: datagouv_title = "Foobar")

      resource = insert(:resource, url: "https://static.data.gouv.fr/file", dataset: dataset)
      assert DB.Resource.hosted_on_datagouv?(resource)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      last_year = Date.utc_today().year - 1

      insert(:dataset_monthly_metric,
        dataset_datagouv_id: dataset.datagouv_id,
        year_month: "#{last_year}-12",
        metric_name: :downloads,
        count: 120_250
      )

      assert dataset |> DB.Repo.preload(:resources) |> TransportWeb.PageView.show_downloads_stats?()

      conn =
        conn
        |> init_test_session(current_user: %{})
        |> get(page_path(conn, :espace_producteur))

      # `is_producer` attribute has been set for the current user
      assert %{"is_producer" => true} = conn |> get_session(:current_user)

      {:ok, doc} = conn |> html_response(200) |> Floki.parse_document()
      assert Floki.find(doc, ".message--error") == []

      assert doc |> Floki.find(".dataset-item h5") |> Enum.map(&(&1 |> Floki.text() |> String.trim())) == [
               datagouv_title
             ]
    end

    test "download stats are displayed", %{conn: conn} do
      # A dataset with a resource hosted on data.gouv.fr
      %DB.Dataset{organization_id: organization_id} = dataset = insert(:dataset, datagouv_title: "A")
      resource = insert(:resource, url: "https://static.data.gouv.fr/file", dataset: dataset)

      # Another dataset but the resource is not hosted on data.gouv.fr
      %DB.Dataset{} = other_dataset = insert(:dataset, datagouv_title: "B", organization_id: organization_id)
      other_resource = insert(:resource, url: "https://example.com/file", dataset: other_dataset)

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      last_year = Date.utc_today().year - 1

      insert(:dataset_monthly_metric,
        dataset_datagouv_id: dataset.datagouv_id,
        year_month: "#{last_year}-12",
        metric_name: :downloads,
        count: 50_250
      )

      insert(:dataset_monthly_metric,
        dataset_datagouv_id: dataset.datagouv_id,
        year_month: "#{last_year}-11",
        metric_name: :downloads,
        count: 70_000
      )

      insert(:dataset_monthly_metric,
        dataset_datagouv_id: other_dataset.datagouv_id,
        year_month: "#{last_year}-11",
        metric_name: :downloads,
        count: 100_000
      )

      parsed_document =
        conn
        |> init_test_session(current_user: %{})
        |> get(page_path(conn, :espace_producteur))
        |> html_response(200)
        |> Floki.parse_document!()

      # Download stats for last year are displayed only for the dataset
      # with at least a resource hosted on data.gouv.fr
      assert DB.Resource.hosted_on_datagouv?(resource)
      refute DB.Resource.hosted_on_datagouv?(other_resource)

      assert dataset |> DB.Repo.preload(:resources) |> TransportWeb.PageView.show_downloads_stats?()
      refute other_dataset |> DB.Repo.preload(:resources) |> TransportWeb.PageView.show_downloads_stats?()

      assert %{dataset.datagouv_id => 50_250 + 70_000} ==
               DB.DatasetMonthlyMetric.downloads_for_year([dataset], last_year)

      [first_dataset, second_dataset] = parsed_document |> Floki.find(".dataset-item")
      assert first_dataset |> Floki.text() =~ "120 k téléchargements en #{last_year}"
      refute second_dataset |> Floki.text() =~ "téléchargements"
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
      conn =
        conn
        |> init_test_session(current_user: %{"is_producer" => true})
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
      conn =
        conn
        |> init_test_session(current_user: %{"is_producer" => false})
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
    espace_producteur_path = page_path(conn, :espace_producteur, utm_campaign: "menu_dropdown")

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
