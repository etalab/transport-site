defmodule TransportWeb.EspaceProducteur.NotificationLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox
  import Ecto.Query

  @endpoint TransportWeb.Endpoint
  @url "/espace_producteur/notifications"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "requires login" do
    conn = build_conn()
    conn = get(conn, @url)
    assert html_response(conn, 302)
  end

  test "displays existing subscriptions" do
    %DB.Dataset{id: dataset_id, organization_id: organization_id} = insert(:dataset, custom_title: "Mon super JDD")
    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :user
    )

    Datagouvfr.Client.User.Mock
    |> expect(:get, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
    content = conn |> get(@url) |> html_response(200)
    assert content =~ "Mon super JDD"
  end

  test "toggle on and then off a notification" do
    %DB.Dataset{id: dataset_id, organization_id: organization_id} = insert(:dataset, custom_title: "Mon super JDD")
    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})

    Datagouvfr.Client.User.Mock
    |> expect(:get, 2, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

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

  @tag :focus
  test "only have correct notifications showing" do
    %DB.Organization{id: organization_id} = insert(:organization)
    %DB.Organization{id: foreign_organization_id} = insert(:organization)

    %DB.Dataset{id: dataset_id, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon super JDD", organization_id: organization_id)

    %DB.Contact{id: contact_id} =
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

    %DB.Contact{id: foreign_contact} =
      insert_contact(%{first_name: "Mikhaïl", last_name: "Karlov", organizations: [%{id: foreign_organization_id}]})

    insert(:notification_subscription,
      contact_id: contact_id_2,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :user
    )

    # Here our team subscribed also a mailing list
    insert(:notification_subscription,
      contact_id: mailing_list_id,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :admin
    )

    # It’s a trap! We subscribed a foreign contact because there wasn’t yet reuser notifications
    insert(:notification_subscription,
      contact_id: foreign_contact,
      dataset_id: dataset_id,
      reason: :expiration,
      role: :producer,
      source: :user
    )

    Datagouvfr.Client.User.Mock
    |> expect(:get, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
    content = conn |> get(@url) |> html_response(200)
    assert content =~ "Autres abonnés : Liste de diffusion service transport, Marina Loiseau"
    refute content =~ "Mikhaïl Karlov"
  end

  test "toggle all on and off" do
    %DB.Dataset{id: dataset_id_1, organization_id: organization_id} = insert(:dataset, custom_title: "Mon super JDD")

    %DB.Dataset{id: dataset_id_2, organization_id: ^organization_id} =
      insert(:dataset, custom_title: "Mon autre JDD", organization_id: organization_id)

    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

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

    conn = build_conn() |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})

    Datagouvfr.Client.User.Mock
    |> expect(:get, 2, fn _ -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

    conn = conn |> get(@url)

    {:ok, view, _html} = live(conn)

    assert [^notification] = DB.NotificationSubscription |> DB.Repo.all()

    render_change(view, "toggle-all", %{"action" => "turn_on"})

    notifications =
      DB.NotificationSubscription
      |> select([n], [n.dataset_id, n.reason])
      |> order_by([n], [n.dataset_id, n.reason])
      |> DB.Repo.all()

    assert [
             [^dataset_id_1, :dataset_with_error],
             [^dataset_id_1, :expiration],
             [^dataset_id_1, :resource_unavailable],
             [^dataset_id_2, :dataset_with_error],
             [^dataset_id_2, :expiration],
             [^dataset_id_2, :resource_unavailable]
           ] = notifications

    render_change(view, "toggle-all", %{"action" => "turn_off"})

    assert [] = DB.NotificationSubscription |> DB.Repo.all()
  end
end
