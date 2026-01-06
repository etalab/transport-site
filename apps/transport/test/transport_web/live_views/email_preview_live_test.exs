defmodule TransportWeb.Backoffice.EmailPreviewLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import DB.Factory
  import Phoenix.LiveViewTest

  doctest TransportWeb.Backoffice.EmailPreviewLive, import: true

  @endpoint TransportWeb.Endpoint
  @url "/backoffice/email_preview"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    {:ok, conn: build_conn()}
  end

  test "requires login", %{conn: conn} do
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  test "displays the expected data", %{conn: conn} do
    insert(:dataset, type: "public-transit", custom_title: "Hello")
    insert(:dataset, type: "public-transit", custom_title: "Hello")

    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    conn =
      conn
      |> init_test_session(%{
        current_user: %{"id" => contact.datagouv_user_id, "is_admin" => true},
        csp_nonce_value: "nonce"
      })
      |> get(@url)

    {:ok, view, _html} = live(conn)

    assert view |> render() |> Floki.parse_document!() |> Floki.find("h1") |> Floki.text() == "Email preview"

    form = view |> element("form")

    assert ["Bienvenue ! Découvrez votre Espace producteur"] == form |> search_by_value("Bienvenue") |> subjects()
    assert ["Loi climat et résilience : suivi des jeux de données"] == form |> search_by_value("climat") |> subjects()

    assert [
             "Erreurs détectées dans le jeu de données Hello",
             "Gestion de vos favoris dans votre espace réutilisateur",
             "Hello : ressources modifiées",
             "Loi climat et résilience : suivi des jeux de données",
             "Nouveaux commentaires sur transport.data.gouv.fr",
             "Nouveaux jeux de données référencés",
             "Ressources indisponibles dans le jeu de données Hello",
             "Suivi des jeux de données favoris arrivant à expiration"
           ] == form |> search_by_value("reuser") |> subjects()

    assert form |> search_by_value("") |> subjects() |> Enum.count() >= 15
  end

  test "all emails in Transport.UserNotifier are present" do
    insert(:dataset, type: "public-transit")
    insert(:dataset, type: "public-transit")

    contact = insert_contact(%{datagouv_user_id: Ecto.UUID.generate()})

    {:ok, %Phoenix.LiveView.Socket{assigns: %{emails: emails}}} =
      TransportWeb.Backoffice.EmailPreviewLive.mount(
        %{},
        %{"current_user" => %{"id" => contact.datagouv_user_id, "is_admin" => true}, "csp_nonce_value" => "nonce"},
        %Phoenix.LiveView.Socket{}
      )

    assert Transport.UserNotifier.__info__(:functions)
           |> Enum.map(fn {function, _arity} -> function end)
           |> Enum.reject(&(&1 in [:resource_titles, :render_body, :expiration_email_subject]))
           |> MapSet.new() == emails |> Enum.map(&elem(&1, 0)) |> MapSet.new()
  end

  defp search_by_value(%Phoenix.LiveViewTest.Element{} = el, value) do
    render_change(el, %{_target: ["search"], search: value})
  end

  defp subjects(%Phoenix.LiveViewTest.View{} = view), do: view |> render() |> subjects()

  defp subjects(content) when is_binary(content) do
    content
    |> Floki.parse_document!()
    |> Floki.find(~s|[data-name="subject"]|)
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end
end
