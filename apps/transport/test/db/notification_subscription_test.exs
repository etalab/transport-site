defmodule DB.NotificationSubscriptionTest do
  use ExUnit.Case, async: true
  import DB.Factory
  alias DB.NotificationSubscription

  doctest NotificationSubscription, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "changeset" do
    contact = insert_contact()
    dataset = insert(:dataset)
    changeset = fn args -> NotificationSubscription.changeset(%NotificationSubscription{}, args) end

    # valid cases
    assert %Ecto.Changeset{valid?: true} =
             changeset.(%{
               role: :reuser,
               source: :admin,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: contact.id
             })

    assert %Ecto.Changeset{valid?: true} =
             changeset.(%{
               role: :producer,
               source: :admin,
               reason: :expiration,
               contact_id: contact.id,
               dataset_id: dataset.id
             })

    assert {:error, %Ecto.Changeset{valid?: false, errors: [dataset: {"does not exist", _}]}} =
             %{
               source: :admin,
               role: :producer,
               reason: :expiration,
               contact_id: contact.id,
               dataset_id: -1
             }
             |> changeset.()
             |> DB.Repo.insert()

    # `contact_id` can never be blank and should exist
    assert %Ecto.Changeset{valid?: false, errors: [contact_id: {"can't be blank", [validation: :required]}]} =
             changeset.(%{
               source: :admin,
               role: :reuser,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: nil
             })

    assert {:error, %Ecto.Changeset{valid?: false, errors: [contact: {"does not exist", _}]}} =
             %{
               source: :admin,
               role: :reuser,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: -1
             }
             |> changeset.()
             |> DB.Repo.insert()

    # `source` and `role` are enums
    assert %Ecto.Changeset{
             valid?: false,
             errors: [
               reason: {"is not allowed for the given role", _},
               source: {"is invalid", _},
               role: {"is invalid", _}
             ]
           } =
             changeset.(%{
               role: :foo,
               source: :foo,
               reason: :datasets_switching_climate_resilience_bill,
               contact_id: contact.id
             })

    # Some reasons can’t be possible depending on dataset presence or role
    assert %Ecto.Changeset{
             valid?: false,
             errors: [
               {:reason, {"is not allowed for the given role", _}}
             ]
           } =
             changeset.(%{
               role: :producer,
               source: :admin,
               reason: :resources_changed,
               contact_id: contact.id,
               dataset_id: dataset.id
             })

    assert %Ecto.Changeset{
             valid?: false,
             errors: [reason: {"is not allowed for the given dataset presence", _}]
           } =
             changeset.(%{
               source: :admin,
               role: :producer,
               reason: :expiration,
               contact_id: contact.id,
               dataset_id: nil
             })

    # Some reasons are only there to create individual notifications and are not allowed as subscriptions
    assert %Ecto.Changeset{
             valid?: false,
             errors: [reason: {"is not allowed for subscription", _}]
           } =
             changeset.(%{
               source: :admin,
               role: :producer,
               reason: :periodic_reminder_producers,
               contact_id: contact.id,
               dataset_id: nil
             })
  end

  test "delete a subscription attached to a notification" do
    contact = insert_contact()

    ns =
      insert(:notification_subscription, %{
        reason: :daily_new_comments,
        source: :admin,
        contact_id: contact.id,
        role: :producer
      })
      |> DB.Repo.preload(:contact)

    %DB.Notification{} = notification = DB.Notification.insert!(ns, %{})

    DB.Repo.delete!(ns)

    %DB.Notification{notification_subscription_id: nil} = DB.Repo.reload!(notification)
  end
end
