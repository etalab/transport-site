defmodule Transport.NotifiersTest do
  @moduledoc """
  This module is just there to run the doctests of the notifiers, which have been moved from other modules.
  """

  use ExUnit.Case, async: true
  import DB.Factory
  doctest Transport.UserNotifier, import: true
  doctest Transport.AdminNotifier, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "Old tests from DataChecker" do
    test "count_archived_datasets" do
      insert(:dataset, is_active: true, archived_at: nil)
      insert(:dataset, is_active: true, archived_at: DateTime.utc_now())
      insert(:dataset, is_active: false, archived_at: DateTime.utc_now())

      assert 1 == Transport.AdminNotifier.count_archived_datasets()
    end

    test "with no subscriptions from producers" do
      insert(:notification_subscription, %{
        reason: :expiration,
        source: :user,
        role: :reuser,
        contact: insert_contact(),
        dataset: dataset = insert(:dataset)
      })

      refute Transport.AdminNotifier.has_expiration_notifications?(dataset)
      assert "❌ pas de notification automatique" == Transport.AdminNotifier.expiration_notification_enabled_str(dataset)
    end
  end

  test "with a subscription from a producer" do
    dataset = insert(:dataset)

    insert(:notification_subscription, %{
      reason: :dataset_with_error,
      source: :admin,
      role: :producer,
      contact: insert_contact(),
      dataset: dataset
    })

    refute Transport.AdminNotifier.has_expiration_notifications?(dataset)

    insert(:notification_subscription, %{
      reason: :expiration,
      source: :admin,
      role: :producer,
      contact: insert_contact(),
      dataset: dataset
    })

    assert Transport.AdminNotifier.has_expiration_notifications?(dataset)
    assert "✅ notification automatique" == Transport.AdminNotifier.expiration_notification_enabled_str(dataset)
  end
end
