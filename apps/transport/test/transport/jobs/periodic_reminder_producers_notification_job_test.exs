defmodule Transport.Test.Transport.Jobs.PeriodicReminderProducersNotificationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  # import Ecto.Query
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.PeriodicReminderProducersNotificationJob

  doctest PeriodicReminderProducersNotificationJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "enqueues jobs" do
    test "discards if not the first Monday of the month" do
      assert {:discard, _} =
               perform_job(PeriodicReminderProducersNotificationJob, %{}, inserted_at: ~U[2023-07-28 09:00:00Z])
    end

    test "enqueues jobs for each contact" do
      dataset = insert(:dataset, organization_id: org_id = Ecto.UUID.generate())
      # Contact should be kept: it doesn't have orgs set but it's subscribed as a producer
      %DB.Contact{id: contact_id_without_org} = insert_contact()

      insert(:notification_subscription,
        source: :admin,
        role: :producer,
        reason: :expiration,
        dataset: dataset,
        contact_id: contact_id_without_org
      )

      # Contact should be ignored: it's a reuser
      insert(:notification_subscription,
        source: :admin,
        role: :reuser,
        reason: :expiration,
        dataset: dataset,
        contact: insert_contact()
      )

      # Contact should be kept: no subscriptions but member of an org with published datasets
      %DB.Contact{id: contact_id_with_org} =
        insert_contact(%{
          organizations: [
            %{
              "acronym" => nil,
              "badges" => [],
              "id" => org_id,
              "logo" => "https://example.com/original.png",
              "logo_thumbnail" => "https://example.com/100.png",
              "name" => "Big Corp",
              "slug" => "foo"
            }
          ]
        })

      assert :ok ==
               perform_job(PeriodicReminderProducersNotificationJob, %{},
                 inserted_at: scheduled_at = ~U[2023-07-03 09:00:00.000000Z]
               )

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.PeriodicReminderProducersNotificationJob",
                 args: %{"contact_id" => ^contact_id_with_org},
                 scheduled_at: ^scheduled_at,
                 state: "scheduled"
               },
               %Oban.Job{
                 worker: "Transport.Jobs.PeriodicReminderProducersNotificationJob",
                 args: %{"contact_id" => ^contact_id_without_org},
                 scheduled_at: ^scheduled_at,
                 state: "scheduled"
               }
             ] = all_enqueued()
    end
  end
end
