defmodule TransportWeb.Live.NotificationsLiveTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.LiveCase
  import DB.Factory
  import Ecto.Query
  import Mox
  import Phoenix.LiveViewTest

  @producer_url espace_producteur_path(TransportWeb.Endpoint, :notifications)
  @reuser_url reuser_space_path(TransportWeb.Endpoint, :notifications)

  @dataset_notifications_path ~s|form table[data-content="dataset-notifications"]|
  @platform_wide_path ~s|div[data-content="platform-wide-notifications"] form table|

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "requires login" do
    test "as a producer", %{conn: conn} do
      conn = conn |> get(@producer_url)
      assert redirected_to(conn, 302) == page_path(conn, :infos_producteurs)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    end

    test "as a reuser", %{conn: conn} do
      conn = conn |> get(@reuser_url)
      assert redirected_to(conn, 302) == page_path(conn, :infos_reutilisateurs)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Vous devez être préalablement connecté"
    end
  end

  test "displays existing subscriptions for a producer", %{conn: conn} do
    %DB.Organization{id: organization_id} = insert(:organization)

    %DB.Dataset{id: dataset_id, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

    other_dataset = insert(:dataset)

    %DB.Contact{id: contact_id} =
      insert_contact(%{
        datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
        organizations: [%{id: organization_id}]
      })

    other_contact = insert_contact()

    insert_admin()

    %DB.NotificationSubscription{id: subscription_id} =
      insert(:notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: :expiration,
        role: :producer,
        source: :user
      )

    # Ignored: another dataset
    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: other_dataset.id,
      reason: :dataset_with_error,
      role: :reuser,
      source: :user
    )

    # Ignored: another contact
    insert(:notification_subscription,
      contact_id: other_contact.id,
      dataset_id: dataset_id,
      reason: :dataset_with_error,
      role: :reuser,
      source: :user
    )

    # This notification shouldn’t exist as the reason isn’t a producer one, but is there in database
    # It should be filtered out
    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: dataset_id,
      reason: :resources_changed,
      role: :producer,
      source: :user
    )

    Datagouvfr.Client.User.Mock
    |> expect(:me, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})
    content = conn |> get(@producer_url) |> html_response(200)
    assert content =~ "Mon super JDD"

    doc = content |> Floki.parse_document!()

    [{"input", switch_attr, []}] =
      doc
      |> Floki.find("#{@dataset_notifications_path} tr td .form__group fieldset .switch input")
      |> Floki.find("[value=true]")
      |> Floki.find("[checked=checked]")

    switch_attr = Map.new(switch_attr)

    assert ["expiration", Integer.to_string(dataset_id), Integer.to_string(subscription_id)] ==
             [switch_attr["id"], switch_attr["phx-value-dataset-id"], switch_attr["phx-value-subscription-id"]]

    # Platform-wide subscriptions are not displayed
    assert [] == doc |> Floki.find(@platform_wide_path)
  end

  test "displays existing subscriptions for a reuser", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset, custom_title: custom_title = "Mon super JDD")
    other_dataset = insert(:dataset)

    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    other_contact = insert_contact()

    insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :follow_button)

    %DB.NotificationSubscription{id: subscription_id} =
      insert(:notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: :expiration,
        role: :reuser,
        source: :user
      )

    # Ignored: another dataset
    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: other_dataset.id,
      reason: :dataset_with_error,
      role: :reuser,
      source: :user
    )

    # Ignored: another contact
    insert(:notification_subscription,
      contact_id: other_contact.id,
      dataset_id: dataset_id,
      reason: :dataset_with_error,
      role: :reuser,
      source: :user
    )

    # Platform-wide reason
    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: nil,
      reason: :daily_new_comments,
      role: :reuser,
      source: :user
    )

    content =
      conn
      |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
      |> get(@reuser_url)
      |> html_response(200)

    assert content =~ custom_title

    [{"input", switch_attr, []}] =
      content
      |> Floki.parse_document!()
      |> Floki.find("#{@dataset_notifications_path} tr td .form__group fieldset .switch input")
      |> Floki.find("[value=true]")
      |> Floki.find("[checked=checked]")

    switch_attr = Map.new(switch_attr)

    assert ["expiration", Integer.to_string(dataset_id), Integer.to_string(subscription_id)] ==
             [switch_attr["id"], switch_attr["phx-value-dataset-id"], switch_attr["phx-value-subscription-id"]]

    # Platform-wide subscription switches
    assert [
             {"input", [{"name", "daily_new_comments"}, {"type", "hidden"}, {"value", "false"}], []},
             {"input",
              [
                {"checked", "checked"},
                {"id", "daily_new_comments"},
                {"name", "daily_new_comments"},
                {"phx-click", "toggle"},
                {"phx-value-action", "turn_off"},
                {"phx-value-reason", "daily_new_comments"},
                {"type", "checkbox"},
                {"value", "true"}
              ], []},
             {"input", [{"name", "new_dataset"}, {"type", "hidden"}, {"value", "false"}], []},
             {"input",
              [
                {"id", "new_dataset"},
                {"name", "new_dataset"},
                {"phx-click", "toggle"},
                {"phx-value-action", "turn_on"},
                {"phx-value-reason", "new_dataset"},
                {"type", "checkbox"},
                {"value", "true"}
              ], []}
           ] ==
             content
             |> Floki.parse_document!()
             |> Floki.find("#{@platform_wide_path} tr td .form__group fieldset .switch input")
  end

  test "displays an error message if we can’t retrieve user orgs (and thus datasets) through data.gouv.fr", %{
    conn: conn
  } do
    Datagouvfr.Client.User.Mock
    |> expect(:me, fn _ -> {:error, %HTTPoison.Error{reason: :nxdomain, id: nil}} end)

    conn = conn |> init_test_session(%{current_user: %{"id" => Ecto.UUID.generate()}, token: %{}})
    content = conn |> get(@producer_url) |> html_response(200)
    assert content =~ "Une erreur a eu lieu lors de la récupération de vos ressources"
  end

  describe "toggle on and then off a notification" do
    test "for a producer", %{conn: conn} do
      %DB.Organization{id: organization_id} = insert(:organization)

      %DB.Dataset{id: dataset_id, organization_id: ^organization_id} =
        insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

      %DB.Contact{id: contact_id} =
        insert_contact(%{
          datagouv_user_id: datagouv_user_id = Ecto.UUID.generate(),
          organizations: [%{id: organization_id}]
        })

      insert_admin()

      conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})

      Datagouvfr.Client.User.Mock
      |> expect(:me, 2, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      {:ok, view, _html} = conn |> get(@producer_url) |> live()

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

    test "for a reuser", %{conn: conn} do
      %DB.Dataset{id: dataset_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
      insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :follow_button)

      {:ok, view, _html} =
        conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}}) |> get(@reuser_url) |> live()

      assert [] = DB.NotificationSubscription |> DB.Repo.all()

      content =
        render_change(view, :toggle, %{
          "dataset-id" => dataset_id,
          "subscription-id" => "",
          "reason" => "expiration",
          "action" => "turn_on"
        })

      assert [
               %{"name" => "daily_new_comments", "phx-value-action" => "turn_on"},
               %{"name" => "new_dataset", "phx-value-action" => "turn_on"}
             ] |> MapSet.new() == dom_platform_wide_reasons(content)

      assert [
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :user,
                 role: :reuser,
                 reason: :expiration,
                 id: subscription_id
               }
             ] = DB.NotificationSubscription |> DB.Repo.all()

      content =
        render_change(view, :toggle, %{
          "dataset-id" => dataset_id,
          "subscription-id" => subscription_id,
          "reason" => "expiration",
          "action" => "turn_off"
        })

      assert [
               %{"name" => "daily_new_comments", "phx-value-action" => "turn_on"},
               %{"name" => "new_dataset", "phx-value-action" => "turn_on"}
             ] |> MapSet.new() == dom_platform_wide_reasons(content)

      assert [] = DB.NotificationSubscription |> DB.Repo.all()
    end

    test "platform-wide reason for a reuser", %{conn: conn} do
      %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

      {:ok, view, _html} =
        conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}}) |> get(@reuser_url) |> live()

      assert [] = DB.NotificationSubscription |> DB.Repo.all()

      content =
        render_change(view, :toggle, %{"reason" => "new_dataset", "action" => "turn_on"})

      assert [
               %{"name" => "daily_new_comments", "phx-value-action" => "turn_on"},
               %{"name" => "new_dataset", "phx-value-action" => "turn_off"}
             ] |> MapSet.new() == dom_platform_wide_reasons(content)

      assert [
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: nil,
                 source: :user,
                 role: :reuser,
                 reason: :new_dataset
               }
             ] = DB.NotificationSubscription |> DB.Repo.all()

      content = render_change(view, :toggle, %{"reason" => "new_dataset", "action" => "turn_off"})

      assert [
               %{"name" => "daily_new_comments", "phx-value-action" => "turn_on"},
               %{"name" => "new_dataset", "phx-value-action" => "turn_on"}
             ] |> MapSet.new() == dom_platform_wide_reasons(content)

      assert [] = DB.NotificationSubscription |> DB.Repo.all()
    end
  end

  test "only have correct colleague notifications showing", %{conn: conn} do
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

    conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})
    content = conn |> get(@producer_url) |> html_response(200)
    assert content =~ "Autres abonnés : Liste de diffusion service transport, Marina Loiseau, Mikhaïl Karlov"
    refute content =~ "Henri Duflot"
  end

  test "toggle all on and off", %{conn: conn} do
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

    conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}, token: %{}})

    Datagouvfr.Client.User.Mock
    |> expect(:me, 2, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    {:ok, view, _html} = conn |> get(@producer_url) |> live()

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

  defp dom_platform_wide_reasons(content) do
    content
    |> Floki.parse_document!()
    |> Floki.find(~s|#{@platform_wide_path} tr td .form__group fieldset .switch input[phx-click="toggle"]|)
    |> Enum.map(fn {"input", attributes, []} -> attributes |> Map.new() |> Map.take(["name", "phx-value-action"]) end)
    |> MapSet.new()
  end
end
