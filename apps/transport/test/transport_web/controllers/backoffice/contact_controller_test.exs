defmodule TransportWeb.Backoffice.ContactControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  alias TransportWeb.Backoffice.ContactController

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "denies access if not logged", %{conn: conn} do
    conn = get(conn, request_path = backoffice_contact_path(conn, :index))
    target_uri = URI.parse(redirected_to(conn, 302))
    assert target_uri.path == "/login/explanation"
    assert target_uri.query == URI.encode_query(redirect_path: request_path)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
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

      table_content = content |> Floki.parse_document!() |> Floki.find("table") |> Floki.text()
      assert table_content =~ "Foo"
      assert table_content =~ "Bar"

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :index, %{"q" => "foo"}))
        |> html_response(200)

      table_content = content |> Floki.parse_document!() |> Floki.find("table") |> Floki.text()
      assert table_content =~ "Foo"
      refute table_content =~ "Bar"
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
               {"li", [], ["first_name : You need to fill either first_name and last_name OR mailing_list_title"]},
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

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Contact mis à jour"
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
      contact =
        DB.Contact.insert!(
          sample_contact_args(%{
            datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
            last_login_at: ~U[2023-04-28 09:54:19.458897Z]
          })
        )

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :edit, contact.id))
        |> html_response(200)

      assert content =~ "Éditer un contact"
      assert content =~ contact.first_name
      assert content =~ contact.last_name
      assert content =~ datagouv_user_id
      assert content =~ "28/04/2023 à 11h54 Europe/Paris"

      args = %{"id" => contact.id, "last_name" => new_last_name = "Bar"}

      conn =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_contact_path(conn, :create, %{"contact" => args}))

      assert redirected_to(conn, 302) == backoffice_contact_path(conn, :index)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Contact mis à jour"
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
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Un contact existe déjà avec cette adresse e-mail"
      assert %DB.Contact{email: ^email} = DB.Repo.reload!(contact)
    end

    test "displays notification subscriptions", %{conn: conn} do
      dataset = insert(:dataset, custom_title: Ecto.UUID.generate())
      contact = DB.Contact.insert!(sample_contact_args())

      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: dataset.id,
        reason: :expiration,
        source: :admin,
        role: :producer
      )

      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: nil,
        reason: :datasets_switching_climate_resilience_bill,
        source: :admin,
        role: :producer
      )

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :edit, contact.id))
        |> html_response(200)

      assert content =~ dataset.custom_title
      assert content =~ "expiration"
      assert content =~ "datasets_switching_climate_resilience_bill"
    end

    test "displays notifications received", %{conn: conn} do
      %DB.Dataset{custom_title: custom_title} = dataset = insert(:dataset)
      contact = DB.Contact.insert!(sample_contact_args())
      other_contact = DB.Contact.insert!(sample_contact_args())

      insert_notification(%{
        contact_id: contact.id,
        reason: :daily_new_comments,
        role: :reuser,
        dataset_id: nil,
        email: contact.email,
        inserted_at: DateTime.utc_now() |> DateTime.add(-5, :hour)
      })

      insert_notification(%{
        contact_id: contact.id,
        reason: :expiration,
        role: :reuser,
        dataset_id: dataset.id,
        email: contact.email
      })

      # Should be ignored: very old
      insert_notification(%{
        contact_id: contact.id,
        reason: :dataset_with_error,
        role: :reuser,
        dataset_id: dataset.id,
        email: contact.email,
        inserted_at: DateTime.utc_now() |> DateTime.add(-6 * 30 - 1, :day)
      })

      # Should be ignored: sent to another contact
      insert_notification(%{
        contact_id: other_contact.id,
        reason: :dataset_with_error,
        role: :reuser,
        dataset_id: dataset.id,
        email: other_contact.email
      })

      content =
        conn
        |> setup_admin_in_session()
        |> get(backoffice_contact_path(conn, :edit, contact.id))
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find("#notifications table tr td")
        |> Enum.map(fn el -> el |> Floki.text() |> String.trim() end)

      assert [
               "reuser",
               "expiration",
               ^custom_title,
               _,
               # 2nd row: a platworm-wide notification
               "reuser",
               "daily_new_comments",
               "-",
               _
             ] = content
    end
  end

  test "delete", %{conn: conn} do
    contact = DB.Contact.insert!(sample_contact_args())

    conn =
      conn
      |> setup_admin_in_session()
      |> post(backoffice_contact_path(conn, :delete, contact.id))

    assert redirected_to(conn, 302) == backoffice_contact_path(conn, :index)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Le contact a été supprimé"
    assert is_nil(DB.Repo.reload(contact))
  end

  test "search_datalist" do
    DB.Contact.insert!(sample_contact_args(%{last_name: "Doe", organization: "FooBar"}))
    DB.Contact.insert!(sample_contact_args(%{last_name: "Oppenheimer", organization: "FooBar"}))

    DB.Contact.insert!(
      sample_contact_args(%{first_name: nil, last_name: nil, organization: "Disney", mailing_list_title: "Data"})
    )

    assert ["Disney", "Doe", "FooBar", "Oppenheimer"] == ContactController.search_datalist()
  end

  test "datasets_datalist" do
    %DB.Dataset{id: active_dataset_id} = insert(:dataset, is_active: true, custom_title: "B")
    %DB.Dataset{id: hidden_dataset_id} = insert(:dataset, is_active: true, is_hidden: true, custom_title: "A")
    insert(:dataset, is_active: false, is_hidden: false, custom_title: "C")

    assert [
             %DB.Dataset{id: ^hidden_dataset_id, custom_title: "A", is_hidden: true},
             %DB.Dataset{id: ^active_dataset_id, custom_title: "B", is_hidden: false}
           ] = ContactController.datasets_datalist()
  end

  defp sample_contact_args(%{} = args \\ %{}) do
    Map.merge(
      %{
        first_name: "John",
        last_name: "Doe",
        email: "john#{Ecto.UUID.generate()}@example.fr",
        job_title: "Boss",
        organization: "Big Corp Inc",
        phone_number: "06 82 22 88 03"
      },
      args
    )
  end
end
