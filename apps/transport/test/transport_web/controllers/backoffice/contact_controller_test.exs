defmodule TransportWeb.Backoffice.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "denies access if not logged", %{conn: conn} do
    conn = get(conn, request_path = backoffice_contact_path(conn, :index))
    target_uri = URI.parse(redirected_to(conn, 302))
    assert target_uri.path == "/login/explanation"
    assert target_uri.query == URI.encode_query(redirect_path: request_path)
    assert get_flash(conn, :info) =~ "Vous devez être préalablement connecté"
  end

  describe "index" do
    test "search contacts", %{conn: conn} do
      DB.Contact.insert!(%{sample_contact_args() | last_name: "Foo"})
      DB.Contact.insert!(%{sample_contact_args() | last_name: "Bar"})

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :index))
        |> html_response(200)

      assert content =~ "Foo"
      assert content =~ "Bar"

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :index, %{"q" => "foo"}))
        |> html_response(200)

      assert content =~ "Foo"
      refute content =~ "Bar"
    end
  end

  describe "new" do
    test "loads the form", %{conn: conn} do
      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :new))
        |> html_response(200)

      assert content =~ "Créer un contact"
      assert [] == content |> Floki.parse_document!() |> Floki.find(".notification")
    end

    test "shows errors", %{conn: conn} do
      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :new, %{"first_name" => "John"}))
        |> html_response(200)

      assert content =~ "Créer un contact"
      doc = content |> Floki.parse_document!()

      assert [
               {"li", [], ["first_name : You need to fill either first_name and last_name OR title"]},
               {"li", [], ["organization : can't be blank"]},
               {"li", [], ["email : can't be blank"]}
             ] == Floki.find(doc, ".notification.error ul li")
    end
  end

  describe "create" do
    test "creates a contact", %{conn: conn} do
      args = %{
        "first_name" => "John",
        "last_name" => "Doe",
        "email" => "john@example.com",
        "organization" => "Corp Inc"
      }

      conn =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_contact_path(conn, :create, %{"contact" => args}))

      assert redirected_to(conn, 302) == backoffice_contact_path(conn, :index)

      assert %DB.Contact{first_name: "John", last_name: "Doe", email: "john@example.com", organization: "Corp Inc"} =
               DB.Repo.one!(DB.Contact)

      assert get_flash(conn, :info) =~ "Contact mis à jour"
    end

    test "redirects when there are errors", %{conn: conn} do
      args = %{"first_name" => "John", "last_name" => "Doe"}

      conn =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_contact_path(conn, :create, %{"contact" => args}))

      assert redirected_to(conn, 302) == backoffice_contact_path(conn, :new) <> "?#{URI.encode_query(args)}"

      assert DB.Contact |> DB.Repo.all() |> Enum.empty?()
    end
  end

  describe "edit" do
    test "can change values", %{conn: conn} do
      contact = DB.Contact.insert!(sample_contact_args())

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :edit, contact.id))
        |> html_response(200)

      assert content =~ "Éditer un contact"
      assert content =~ contact.first_name
      assert content =~ contact.last_name

      args = %{"id" => contact.id, "last_name" => new_last_name = "Bar"}

      conn =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_contact_path(conn, :create, %{"contact" => args}))

      assert redirected_to(conn, 302) == backoffice_contact_path(conn, :index)
      assert get_flash(conn, :info) =~ "Contact mis à jour"
      assert %DB.Contact{last_name: ^new_last_name} = DB.Repo.reload!(contact)
    end

    test "validates changes", %{conn: conn} do
      %DB.Contact{email: other_email} = DB.Contact.insert!(sample_contact_args())
      %DB.Contact{email: email} = contact = DB.Contact.insert!(sample_contact_args())

      conn =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_contact_path(conn, :create, %{"contact" => %{"id" => contact.id, "email" => other_email}}))

      assert redirected_to(conn, 302) == backoffice_contact_path(conn, :index)
      assert get_flash(conn, :error) =~ "Un contact existe déjà avec cette adresse e-mail"
      assert %DB.Contact{email: ^email} = DB.Repo.reload!(contact)
    end

    test "displays notification subscriptions", %{conn: conn} do
      dataset = insert(:dataset, custom_title: Ecto.UUID.generate())
      contact = DB.Contact.insert!(sample_contact_args())

      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: dataset.id,
        reason: :expiration,
        source: :admin
      )

      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: nil,
        reason: :dataset_now_licence_ouverte,
        source: :admin
      )

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :edit, contact.id))
        |> html_response(200)

      assert content =~ dataset.custom_title
      assert content =~ "expiration"
      assert content =~ "dataset_now_licence_ouverte"
    end
  end

  test "delete", %{conn: conn} do
    contact = DB.Contact.insert!(sample_contact_args())

    conn =
      conn
      |> setup_admin_in_session()
      |> post(backoffice_contact_path(conn, :delete, contact.id))

    assert redirected_to(conn, 302) == backoffice_contact_path(conn, :index)
    assert get_flash(conn, :info) =~ "Le contact a été supprimé"
    assert is_nil(DB.Repo.reload(contact))
  end

  defp sample_contact_args do
    %{
      first_name: "John",
      last_name: "Doe",
      email: "john#{Ecto.UUID.generate()}@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: "06 92 22 88 03"
    }
  end
end
