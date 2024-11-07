defmodule TransportWeb.NotificationSubscriptionControllerTest do
  use TransportWeb.ConnCase, async: true
  import Ecto.Query
  import DB.Factory
  @target_html_anchor "#notification_subscriptions"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "create" do
    test "for reasons related to a dataset", %{conn: conn} do
      %DB.Dataset{id: dataset_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = insert_contact()

      args = %{
        "redirect_location" => "dataset",
        "dataset_id" => dataset_id,
        "contact_id" => contact_id,
        "expiration" => "true",
        "resource_unavailable" => "true",
        # Should be ignored because this is not a valid reason
        "ignored_notification_reason" => "true",
        # Ignored because it's set to false (happens only when manipulating requests)
        "dataset_with_error" => "false"
      }

      conn_response =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_notification_subscription_path(conn, :create, args))

      assert redirected_to(conn_response, 302) == backoffice_page_path(conn, :edit, dataset_id) <> @target_html_anchor
      assert Phoenix.Flash.get(conn_response.assigns.flash, :info) =~ "L'abonnement a été créé"

      assert [
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :admin,
                 reason: :expiration
               },
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :admin,
                 reason: :resource_unavailable
               }
             ] = DB.NotificationSubscription |> DB.Repo.all() |> Enum.sort_by(& &1.reason)

      # Sending a request again, but with a new valid reason. Should not try to create duplicates.
      conn_response =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_notification_subscription_path(conn, :create, Map.put(args, "dataset_with_error", "true")))

      assert redirected_to(conn_response, 302) == backoffice_page_path(conn, :edit, dataset_id) <> @target_html_anchor
      assert Phoenix.Flash.get(conn_response.assigns.flash, :info) =~ "L'abonnement a été créé"

      assert Enum.sort([:dataset_with_error, :expiration, :resource_unavailable]) ==
               DB.NotificationSubscription.base_query()
               |> select([notification_subscription: ns], ns.reason)
               |> DB.Repo.all()
               |> Enum.sort()
    end

    test "for reasons not related to datasets", %{conn: conn} do
      %DB.Dataset{id: dataset_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = insert_contact()
      # An existing subscription linked to a dataset
      insert(:notification_subscription,
        dataset_id: dataset_id,
        source: :admin,
        role: :producer,
        contact_id: contact_id,
        reason: :expiration
      )

      assert [
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :admin,
                 reason: :expiration
               }
             ] = DB.NotificationSubscription |> DB.Repo.all()

      args = %{
        "redirect_location" => "contact",
        "contact_id" => contact_id,
        "daily_new_comments" => "true",
        # Not a valid reason, should be ignored
        "foobar" => "true"
      }

      conn_response =
        conn
        |> setup_admin_in_session()
        |> post(backoffice_notification_subscription_path(conn, :create, args))

      assert redirected_to(conn_response, 302) ==
               backoffice_contact_path(conn, :edit, contact_id) <> @target_html_anchor

      assert Phoenix.Flash.get(conn_response.assigns.flash, :info) =~ "Abonnements mis à jour"

      assert [
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: nil,
                 source: :admin,
                 reason: :daily_new_comments
               },
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :admin,
                 reason: :expiration
               }
             ] = DB.NotificationSubscription |> DB.Repo.all() |> Enum.sort_by(& &1.reason)
    end
  end

  test "delete", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    %DB.Contact{id: contact_id} = insert_contact()

    %DB.NotificationSubscription{id: subscription_id} =
      insert(:notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: :expiration,
        source: :admin,
        role: :producer
      )

    conn_response =
      conn
      |> setup_admin_in_session()
      |> delete(backoffice_notification_subscription_path(conn, :delete, subscription_id), %{
        "redirect_location" => "dataset"
      })

    assert redirected_to(conn_response, 302) == backoffice_page_path(conn, :edit, dataset_id) <> @target_html_anchor
    assert Phoenix.Flash.get(conn_response.assigns.flash, :info) =~ "L'abonnement a été supprimé"

    assert DB.NotificationSubscription |> DB.Repo.all() |> Enum.empty?()
  end

  test "delete_for_contact_and_dataset", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    %DB.Contact{id: contact_id} = insert_contact()
    %DB.Contact{id: other_contact_id} = insert_contact()

    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: dataset_id,
      reason: :expiration,
      source: :admin,
      role: :producer
    )

    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: dataset_id,
      reason: :dataset_with_error,
      source: :admin,
      role: :producer
    )

    # A subscription, but for another contact.
    insert(:notification_subscription,
      contact_id: other_contact_id,
      dataset_id: dataset_id,
      reason: :dataset_with_error,
      source: :admin,
      role: :producer
    )

    conn_response =
      conn
      |> setup_admin_in_session()
      |> delete(
        backoffice_notification_subscription_path(conn, :delete_for_contact_and_dataset, contact_id, dataset_id),
        %{"redirect_location" => "dataset"}
      )

    assert redirected_to(conn_response, 302) == backoffice_page_path(conn, :edit, dataset_id) <> @target_html_anchor
    assert Phoenix.Flash.get(conn_response.assigns.flash, :info) =~ "Les abonnements ont été supprimés"

    assert [
             %DB.NotificationSubscription{
               contact_id: ^other_contact_id,
               dataset_id: ^dataset_id,
               reason: :dataset_with_error,
               source: :admin
             }
           ] = DB.NotificationSubscription |> DB.Repo.all()
  end
end
