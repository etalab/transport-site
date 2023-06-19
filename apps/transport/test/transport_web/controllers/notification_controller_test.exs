defmodule TransportWeb.NotificationControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  import Ecto.Query
  import Mox
  import Plug.Test, only: [init_test_session: 2]

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  describe "index" do
    test "redirects if not logged in", %{conn: conn} do
      assert conn |> get(notification_path(conn, :index)) |> redirected_to(302) =~ ~r"^/login/explanation"
    end

    test "displays existing subscriptions", %{conn: conn} do
      %DB.Dataset{id: dataset_id, organization_id: organization_id} = insert(:dataset, custom_title: "Mon super JDD")
      %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

      insert(:notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: :expiration,
        source: :user
      )

      Datagouvfr.Client.User.Mock
      |> expect(:me, fn %Plug.Conn{} -> {:ok, %{"organizations" => [%{"id" => organization_id}]}} end)

      conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
      content = conn |> get(notification_path(conn, :index)) |> html_response(200)
      assert content =~ "Mon super JDD"
    end
  end

  describe "create" do
    test "for reasons related to a dataset", %{conn: conn} do
      %DB.Dataset{id: dataset_id} = insert(:dataset)
      %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

      args = %{
        "dataset_id" => dataset_id,
        "expiration" => "true",
        "resource_unavailable" => "true",
        # Should be ignored because this is not a valid reason
        "ignored_notification_reason" => "true",
        # Ignored because it's set to false (happens only when manipulating requests)
        "dataset_with_error" => "false"
      }

      conn =
        conn
        |> init_test_session(%{
          current_user: %{
            "id" => datagouv_user_id,
            "first_name" => "John",
            "last_name" => "Doe",
            "email" => "john@example.fr"
          }
        })

      conn_response = conn |> post(notification_path(conn, :create, args))

      assert redirected_to(conn_response, 302) == notification_path(conn, :index)
      assert get_flash(conn_response, :info) =~ "La notification a été créée"

      assert [
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :user,
                 reason: :expiration
               },
               %DB.NotificationSubscription{
                 contact_id: ^contact_id,
                 dataset_id: ^dataset_id,
                 source: :user,
                 reason: :resource_unavailable
               }
             ] = DB.NotificationSubscription |> DB.Repo.all() |> Enum.sort_by(& &1.reason)

      # Sending a request again, but with a new valid reason. Should not try to create duplicates.
      conn_response = conn |> post(notification_path(conn, :create, Map.put(args, "dataset_with_error", "true")))

      assert redirected_to(conn_response, 302) == notification_path(conn, :index)
      assert get_flash(conn_response, :info) =~ "La notification a été créée"

      assert Enum.sort([:dataset_with_error, :expiration, :resource_unavailable]) ==
               DB.NotificationSubscription.base_query()
               |> select([notification_subscription: ns], ns.reason)
               |> DB.Repo.all()
               |> Enum.sort()
    end
  end

  test "delete", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})

    %DB.NotificationSubscription{id: subscription_id} =
      insert(:notification_subscription,
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: :expiration,
        source: :user
      )

    conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
    conn_response = conn |> delete(notification_path(conn, :delete, subscription_id))

    assert redirected_to(conn_response, 302) == notification_path(conn, :index)
    assert get_flash(conn_response, :info) =~ "La notification a été supprimée"

    assert DB.NotificationSubscription |> DB.Repo.all() |> Enum.empty?()
  end

  test "delete_for_dataset", %{conn: conn} do
    %DB.Dataset{id: dataset_id} = insert(:dataset)
    %DB.Contact{id: contact_id} = insert_contact(%{datagouv_user_id: datagouv_user_id = Ecto.UUID.generate()})
    %DB.Contact{id: other_contact_id} = insert_contact()

    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: dataset_id,
      reason: :expiration,
      source: :user
    )

    insert(:notification_subscription,
      contact_id: contact_id,
      dataset_id: dataset_id,
      reason: :dataset_with_error,
      source: :user
    )

    # A subscription, but for another contact.
    insert(:notification_subscription,
      contact_id: other_contact_id,
      dataset_id: dataset_id,
      reason: :dataset_with_error,
      source: :user
    )

    conn = conn |> init_test_session(%{current_user: %{"id" => datagouv_user_id}})
    conn_response = conn |> delete(notification_path(conn, :delete_for_dataset, dataset_id))

    assert redirected_to(conn_response, 302) == notification_path(conn, :index)
    assert get_flash(conn_response, :info) =~ "Les notifications ont été supprimées"

    assert [
             %DB.NotificationSubscription{
               contact_id: ^other_contact_id,
               dataset_id: ^dataset_id,
               reason: :dataset_with_error,
               source: :user
             }
           ] = DB.NotificationSubscription |> DB.Repo.all()
  end
end
