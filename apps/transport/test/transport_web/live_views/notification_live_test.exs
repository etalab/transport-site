defmodule TransportWeb.EspaceProducteur.NotificationLiveTest do
  use ExUnit.Case, async: true
  use TransportWeb.LiveCase
  import Phoenix.LiveViewTest
  import DB.Factory
  import Mox

  @endpoint TransportWeb.Endpoint
  @url "/espace_producteur/notifications"

  ## OLD CODE from notification controller

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
end
