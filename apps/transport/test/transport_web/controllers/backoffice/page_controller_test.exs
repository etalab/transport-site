defmodule TransportWeb.Backoffice.PageControllerTest do
  use TransportWeb.ConnCase, async: true
  alias TransportWeb.Backoffice.PageController
  alias TransportWeb.Router.Helpers, as: Routes
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "check availability filter" do
    now = DateTime.utc_now()
    # 10% downtime of 30 days is 72 hours
    hours_ago_73 = now |> DateTime.add(-73 * 60 * 60)
    minute_ago_1 = now |> DateTime.add(-60)

    # dataset 1 : resource always available
    %{id: dataset_id_1} = insert(:dataset)
    insert(:resource, %{dataset_id: dataset_id_1})

    # dataset 2 : 1 resource unavailable
    %{id: dataset_id_2} = insert(:dataset)

    %{id: resource_id_2_1} = insert(:resource, %{dataset_id: dataset_id_2})
    insert(:resource, %{dataset_id: dataset_id_2})

    insert(:resource_unavailability, %{resource_id: resource_id_2_1, start: hours_ago_73, end: minute_ago_1})

    # dataset 3 : all resources unavailable
    %{id: dataset_id_3} = insert(:dataset)

    %{id: resource_id_3_1} = insert(:resource, %{dataset_id: dataset_id_3})
    %{id: resource_id_3_2} = insert(:resource, %{dataset_id: dataset_id_3})

    insert(:resource_unavailability, %{resource_id: resource_id_3_1, start: hours_ago_73, end: minute_ago_1})
    insert(:resource_unavailability, %{resource_id: resource_id_3_2, start: hours_ago_73})

    assert [dataset_id_2, dataset_id_3] == PageController.dataset_with_resource_under_90_availability()
  end

  test "inactive datasets are filtered out" do
    now = DateTime.utc_now()
    hours_ago_73 = now |> DateTime.add(-73 * 60 * 60)
    minute_ago_1 = now |> DateTime.add(-60)

    %{id: dataset_id} = insert(:dataset, %{is_active: false})
    %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id})
    insert(:resource_unavailability, %{resource_id: resource_id, start: hours_ago_73, end: minute_ago_1})

    assert [] == PageController.dataset_with_resource_under_90_availability()
  end

  test "can load the dataset#new page", %{conn: conn} do
    conn
    |> setup_admin_in_session()
    |> get(Routes.backoffice_page_path(conn, :new))
    |> html_response(200)
  end

  test "outdated datasets filter", %{conn: conn} do
    insert_outdated_resource_and_friends(custom_title: "un dataset outdated")
    insert_up_to_date_resource_and_friends(custom_title: "un dataset bien à jour")

    conn1 =
      conn
      |> setup_admin_in_session()
      |> get(Routes.backoffice_page_path(conn, :index))

    assert html_response(conn1, 200) =~ "un dataset outdated"
    assert html_response(conn1, 200) =~ "un dataset bien à jour"

    conn2 =
      conn
      |> setup_admin_in_session()
      |> get(
        Routes.backoffice_page_path(conn, :index, %{"filter" => "outdated", "dir" => "asc", "order_by" => "end_date"})
      )

    assert html_response(conn2, 200) =~ "un dataset outdated"
    refute html_response(conn2, 200) =~ "un dataset bien à jour"
  end

  test "notifications config and notifications sent are displayed", %{conn: conn} do
    organization = insert(:organization)

    dataset =
      insert(:dataset,
        is_active: true,
        datagouv_id: Ecto.UUID.generate(),
        slug: Ecto.UUID.generate(),
        organization_id: organization.id
      )

    insert_notification(%{dataset: dataset, role: :producer, email: "foo@example.fr", reason: :expiration})
    insert_notification(%{dataset: dataset, role: :producer, email: "bar@example.fr", reason: :expiration})

    doc =
      conn
      |> setup_admin_in_session()
      |> get(Routes.backoffice_page_path(conn, :edit, dataset.id))
      |> html_response(200)
      |> Floki.parse_document!()

    assert "bar@example.fr, foo@example.fr" ==
             doc |> Floki.find("#notifications_sent table td:nth-child(3)") |> Floki.text()
  end

  test "notification subscriptions", %{conn: conn} do
    producer = insert_contact(%{last_name: "Dupont"})
    reuser = insert_contact(%{last_name: "Dupond"})

    dataset = insert(:dataset, custom_title: "Super JDD")

    [{producer, :producer}, {reuser, :reuser}]
    |> Enum.each(fn {%DB.Contact{} = contact, role} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :expiration,
        dataset: dataset,
        contact: contact
      )

      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :dataset_with_error,
        dataset: dataset,
        contact: contact
      )
    end)

    doc =
      conn
      |> setup_admin_in_session()
      |> get(Routes.backoffice_page_path(conn, :edit, dataset.id))
      |> html_response(200)
      |> Floki.parse_document!()

    text_for_cell = fn row, cell ->
      doc |> Floki.find("#existing_subscriptions_table tr:nth-child(#{row}) td:nth-child(#{cell})") |> Floki.text()
    end

    assert text_for_cell.(2, 1) =~ "Dupont"
    assert text_for_cell.(2, 2) =~ "dataset_with_error"
    assert text_for_cell.(2, 3) =~ "admin"
    assert text_for_cell.(3, 1) =~ "expiration"
    assert text_for_cell.(3, 2) =~ "admin"

    assert doc |> Floki.find("#reuser_subscriptions") |> Floki.text() |> String.replace(~r/\s/, " ") =~
             "Ainsi que 2 abonnements de 1 réutilisateur."
  end

  test "notifications_sent sort order and grouping works" do
    dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate(), slug: Ecto.UUID.generate())

    now = DateTime.utc_now()
    five_hours_ago = DateTime.add(now, -5, :hour)

    insert_notification_at_datetime(
      %{dataset: dataset, role: :producer, email: "foo@example.fr", reason: :expiration},
      now
    )

    insert_notification_at_datetime(
      %{dataset: dataset, role: :producer, email: "bar@example.fr", reason: :expiration},
      now
    )

    insert_notification_at_datetime(
      %{dataset: dataset, role: :producer, email: "bar@example.fr", reason: :expiration},
      five_hours_ago
    )

    insert_notification_at_datetime(
      %{dataset: dataset, role: :producer, email: "baz@example.fr", reason: :expiration},
      five_hours_ago
    )

    now_truncated = %{DateTime.truncate(now, :second) | second: 0}
    five_hours_ago_truncated = %{DateTime.truncate(five_hours_ago, :second) | second: 0}

    assert [
             {{:expiration, ^now_truncated}, emails_1},
             {{:expiration, ^five_hours_ago_truncated}, emails_2}
           ] = PageController.notifications_sent(dataset)

    assert emails_1 |> Enum.sort() == ["bar@example.fr", "foo@example.fr"]
    assert emails_2 |> Enum.sort() == ["bar@example.fr", "baz@example.fr"]
  end

  test "can download the resources CSV", %{conn: conn} do
    # Being an admin is not enough
    assert %URI{path: "/login/explanation"} =
             conn
             |> setup_admin_in_session()
             |> get(Routes.backoffice_page_path(conn, :download_resources_csv))
             |> redirected_to(302)
             |> URI.parse()

    # Can download the CSV if you provide the secret key in the URL
    assert "fake_export_secret_key" == Application.fetch_env!(:transport, :export_secret_key)

    response =
      conn
      |> get(Routes.backoffice_page_path(conn, :download_resources_csv), %{"export_key" => "fake_export_secret_key"})

    assert response(response, 200)
    assert response_content_type(response, :csv) == "text/csv; charset=utf-8"

    assert Plug.Conn.get_resp_header(response, "content-disposition") == [
             ~s(attachment; filename="ressources-#{Date.utc_today() |> Date.to_iso8601()}.csv")
           ]
  end

  describe "contacts_in_org" do
    test "org is not set" do
      dataset = insert(:dataset, organization_id: nil)
      assert [] == PageController.contacts_in_org(dataset |> DB.Repo.preload(organization_object: :contacts))
    end

    test "dataset is nil" do
      assert [] == PageController.contacts_in_org(nil)
    end

    test "with contacts" do
      organization = insert(:organization)
      dataset = insert(:dataset, organization_id: organization.id)
      %DB.Contact{id: contact_id} = insert_contact(%{organizations: [organization |> Map.from_struct()]})

      assert [%DB.Contact{id: ^contact_id}] =
               PageController.contacts_in_org(dataset |> DB.Repo.preload(organization_object: :contacts))
    end
  end

  describe "subscriptions_by_producer" do
    test "ignore reusers" do
      producer_1 = insert_contact(%{last_name: "Dupont"})
      producer_2 = insert_contact(%{last_name: "Loiseau"})

      admin_producer =
        insert_contact(%{
          last_name: "Castafiore",
          organizations: [sample_org(%{"name" => "Point d'Accès National transport.data.gouv.fr"})]
        })

      reuser = insert_contact(%{last_name: "Dupond"})

      dataset = insert(:dataset, custom_title: "Super JDD")

      [{producer_1, :producer}, {producer_2, :producer}, {reuser, :reuser}, {admin_producer, :producer}]
      |> Enum.each(fn {%DB.Contact{} = contact, role} ->
        insert(:notification_subscription,
          source: :admin,
          role: role,
          reason: :expiration,
          dataset: dataset,
          contact: contact
        )

        insert(:notification_subscription,
          source: :admin,
          role: role,
          reason: :dataset_with_error,
          dataset: dataset,
          contact: contact
        )
      end)

      dataset = PageController.load_dataset(dataset.id)

      subscriptions_by_producer = PageController.subscriptions_by_producer(dataset)

      contacts =
        subscriptions_by_producer
        |> Enum.map(fn {contact, _} -> contact end)

      # contact are sorted by last name & reason, and restricted to producers
      assert Enum.map(contacts, & &1.id) == [admin_producer.id, producer_1.id, producer_2.id]

      assert Enum.all?(subscriptions_by_producer, fn {_, subscriptions} ->
               Enum.map(subscriptions, & &1.reason) == [:dataset_with_error, :expiration]
             end)
    end
  end

  defp sample_org(%{} = args) do
    Map.merge(
      %{
        "acronym" => nil,
        "badges" => [],
        "id" => Ecto.UUID.generate(),
        "logo" => "https://example.com/original.png",
        "logo_thumbnail" => "https://example.com/100.png",
        "name" => "Big Corp",
        "slug" => "foo" <> Ecto.UUID.generate()
      },
      args
    )
  end

  defp insert_notification_at_datetime(%{} = args, %DateTime{} = datetime) do
    args
    |> insert_notification()
    |> Ecto.Changeset.change(%{inserted_at: datetime})
    |> DB.Repo.update!()
  end
end
