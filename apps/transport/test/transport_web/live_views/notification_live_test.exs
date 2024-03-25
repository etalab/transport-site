defmodule TransportWeb.EspaceProducteur.NotificationLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox
  import Ecto.Query

  @endpoint TransportWeb.Endpoint
  @url "/espace_producteur/notifications"

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "requires login" do
    conn = build_conn()
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  test "displays existing subscriptions" do
    %DB.Organization{id: organization_id} = insert(:organization)

    %DB.Dataset{id: dataset_id, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

    %DB.Contact{id: contact_id} =
      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [%{id: organization_id}]
      })

    insert_admin()

    %DB.NotificationSubscription{id: subscription_id} =
      insert(:notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: :expiration,
        role: :producer,
        source: :user
      )

    Datagouvfr.Client.User.Mock
    |> expect(:me, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})
    content = conn |> get(@url) |> html_response(200)
    assert content =~ "Mon super JDD"

    doc = content |> Floki.parse_document!()

    [{"input", switch_attr, []}] =
      doc
      |> Floki.find(".producer-actions .container .panel table tr td .form__group fieldset .switch input")
      |> Floki.find("[value=true]")
      |> Floki.find("[checked=checked]")

    switch_attr = Map.new(switch_attr)

    assert ["expiration", Integer.to_string(dataset_id), Integer.to_string(subscription_id)] ==
             [switch_attr["id"], switch_attr["phx-value-dataset-id"], switch_attr["phx-value-subscription-id"]]
  end

  test "displays an error message if we can’t retrieve user orgs (and thus datasets) through data.gouv.fr" do
    Datagouvfr.Client.User.Mock
    |> expect(:me, fn _ -> {:error, %HTTPoison.Error{reason: :nxdomain, id: nil}} end)

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => Ecto.UUID.generate()}, token: %{}})
    content = conn |> get(@url) |> html_response(200)
    assert content =~ "Une erreur a eu lieu lors de la récupération de vos ressources"
  end

  test "toggle on and then off a notification" do
    %DB.Organization{id: organization_id} = insert(:organization)

    %DB.Dataset{id: dataset_id, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

    %DB.Contact{id: contact_id} =
      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [%{id: organization_id}]
      })

    insert_admin()

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})

    Datagouvfr.Client.User.Mock
    |> expect(:me, 2, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = conn |> get(@url)

    {:ok, view, _html} = live(conn)

    assert [] = DB.NotificationSubscription |> DB.Repo.all()

    render_change(view, :toggle, %{
      "dataset-id" => dataset_id,
      "subscription-id" => "",
      "reason" => "expiration",
      "action" => "turn_on"
    })

    assert [
             %DB.NotificationSubscription{
               contact_id: ^contact_id,
               dataset_id: ^dataset_id,
               source: :user,
               role: :producer,
               reason: :expiration,
               id: subscription_id
             }
           ] = DB.NotificationSubscription |> DB.Repo.all()

    render_change(view, :toggle, %{
      "dataset-id" => dataset_id,
      "subscription-id" => subscription_id,
      "reason" => "expiration",
      "action" => "turn_off"
    })

    assert [] = DB.NotificationSubscription |> DB.Repo.all()
  end

  test "only have correct colleague notifications showing" do
    %DB.Organization{id: organization_id} = insert(:organization)
    %DB.Organization{id: foreign_organization_id} = insert(:organization)

    %DB.Dataset{id: dataset_id, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

    %DB.Contact{id: _contact_id} =
      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [%{id: organization_id}]
      })

    %DB.Contact{id: contact_id_2} =
      insert_contact(%{first_name: "Marina", last_name: "Loiseau", organizations: [%{id: organization_id}]})

    %DB.Contact{id: mailing_list_id} =
      insert_contact(%{
        first_name: "",
        last_name: "",
        mailing_list_title: "Liste de diffusion service transport",
        organizations: [%{id: organization_id}]
      })

    %DB.Contact{id: contact_id_3} =
      insert_contact(%{first_name: "Henri", last_name: "Duflot", organizations: [%{id: organization_id}]})

    %DB.Contact{id: foreign_contact} =
      insert_contact(%{first_name: "Mikhaïl", last_name: "Karlov", organizations: [%{id: foreign_organization_id}]})

    insert_admin()

    # Should show, normal colleague
    insert(:notification_subscription,
      contact_id: contact_id_2,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :admin
    )

    # Here our team subscribed also a mailing list, should show
    insert(:notification_subscription,
      contact_id: mailing_list_id,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :admin
    )

    # We subscribed a foreign contact, this should show as well.
    # We’re ok with that: we suscribe people from other orgs to our datasets but we want producers to know it.
    # This is because they’re kind of colleagues – it may be the operator vs transport authority.
    insert(:notification_subscription,
      contact_id: foreign_contact,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :user
    )

    # This is a trap: it’s a reuser notification
    insert(:notification_subscription,
      contact_id: contact_id_3,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :reuser,
      source: :user
    )

    Datagouvfr.Client.User.Mock
    |> expect(:me, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})
    content = conn |> get(@url) |> html_response(200)
    assert content =~ "Autres abonnés : Liste de diffusion service transport, Marina Loiseau, Mikhaïl Karlov"
    refute content =~ "Henri Duflot"
  end

  test "toggle all on and off" do
    %DB.Organization{id: organization_id} = insert(:organization)

    %DB.Dataset{id: dataset_id_1, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

    %DB.Dataset{id: dataset_id_2, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon autre JDD", organization_id: organization_id)

    %DB.Contact{id: contact_id} =
      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [%{id: organization_id}]
      })

    insert_admin()

    # Let’s have at least one subscription in base

    notification =
      %DB.NotificationSubscription{
        contact_id: ^contact_id,
        dataset_id: ^dataset_id_1,
        reason: :expiration,
        role: :producer,
        source: :user
      } =
      insert(
        :notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id_1,
        reason: :expiration,
        role: :producer,
        source: :user
      )

    not_to_be_deleted_notification =
      %DB.NotificationSubscription{
        contact_id: ^contact_id,
        reason: :new_dataset,
        role: :producer,
        source: :admin
      } =
      insert(
        :notification_subscription,
        contact_id: contact_id,
        dataset_id: nil,
        reason: :new_dataset,
        role: :producer,
        source: :admin
      )

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})

    Datagouvfr.Client.User.Mock
    |> expect(:me, 2, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = conn |> get(@url)

    {:ok, view, _html} = live(conn)

    assert [^notification, ^not_to_be_deleted_notification] =
             DB.NotificationSubscription |> order_by(asc: :id) |> DB.Repo.all()

    render_change(view, "toggle-all", %{"action" => "turn_on"})

    notifications =
      DB.NotificationSubscription
      |> select([n], [n.dataset_id, n.reason])
      |> order_by([n], [n.dataset_id, n.reason])
      |> DB.Repo.all()

    assert [
             [dataset_id_1, :dataset_with_error],
             [dataset_id_1, :expiration],
             [dataset_id_1, :resource_unavailable],
             [dataset_id_2, :dataset_with_error],
             [dataset_id_2, :expiration],
             [dataset_id_2, :resource_unavailable],
             [nil, :new_dataset]
           ] == notifications

    render_change(view, "toggle-all", %{"action" => "turn_off"})

    assert [^not_to_be_deleted_notification] = DB.NotificationSubscription |> DB.Repo.all()
  end

  defp insert_admin do
    insert_contact(%{
      organizations: [
        %{
          "name" => "Point d'Accès National transport.data.gouv.fr",
          "acronym" => nil,
          "badges" => [],
          "id" => Ecto.UUID.generate(),
          "logo" => "https://example.com/original.png",
          "logo_thumbnail" => "https://example.com/100.png",
          "slug" => "foo" <> Ecto.UUID.generate()
        }
      ]
    })
  end
end
