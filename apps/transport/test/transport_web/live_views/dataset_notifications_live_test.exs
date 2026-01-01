defmodule TransportWeb.Live.DatasetNotificationsLiveTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.LiveCase
  import DB.Factory
  import Mox
  import Phoenix.LiveViewTest

  setup do
    :verify_on_exit!
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "displays existing subscriptions", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset, custom_title: custom_title = "Mon super JDD")
    other_dataset = insert(:dataset)

    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

    other_contact = insert_contact()

    insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :follow_button)
    insert(:dataset_follower, contact_id: contact_id, dataset_id: other_dataset.id, source: :follow_button)

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

    # Ignored: platform-wide reason
    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: nil,
      reason: :daily_new_comments,
      role: :reuser,
      source: :user
    )

    Datagouvfr.Client.Organization.Mock
    |> expect(:get, 2, fn _organization_id, [restrict_fields: true] ->
      {:ok, %{"members" => []}}
    end)

    Datagouvfr.Client.Discussions.Mock |> expect(:get, 2, fn _datagouv_id -> [] end)

    content =
      conn
      |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
      |> get(reuser_space_path(conn, :datasets_edit, dataset_id))
      |> html_response(200)

    assert content =~ custom_title

    inputs =
      content
      |> Floki.parse_document!()
      |> Floki.find(~s|table tr td .form__group fieldset .switch input|)

    # Toggled reasons
    assert [
             %{
               "id" => "expiration",
               "phx-value-dataset-id" => Integer.to_string(dataset_id),
               "phx-value-subscription-id" => Integer.to_string(subscription_id)
             }
           ] ==
             inputs
             |> keep_checked_inputs()
             |> Enum.map(fn {"input", attributes, []} ->
               attributes |> Map.new() |> Map.take(["id", "phx-value-dataset-id", "phx-value-subscription-id"])
             end)

    # Untoggled reasons
    assert ["dataset_with_error", "resource_unavailable", "resources_changed"] ==
             inputs
             |> reject_checked_inputs()
             |> Enum.map(fn {"input", attributes, []} ->
               attributes |> Map.new() |> Map.fetch!("name")
             end)
  end

  test "toggle on and then off", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    insert(:dataset_follower, contact_id: contact_id, dataset_id: dataset_id, source: :follow_button)

    {:ok, view, _html} =
      live_isolated(conn, TransportWeb.Live.DatasetNotificationsLive,
        session: %{
          "current_user" => %{"id" => datagouv_user_id},
          "dataset_id" => dataset_id,
          "locale" => "fr"
        }
      )

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
               role: :reuser,
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

  defp keep_checked_inputs(inputs) do
    Enum.filter(inputs, fn {"input", attributes, []} -> {"checked", "checked"} in attributes end)
  end

  defp reject_checked_inputs(inputs) do
    Enum.reject(inputs, fn {"input", attributes, []} ->
      Enum.any?([{"checked", "checked"}, {"type", "hidden"}], &(&1 in attributes))
    end)
  end
end
