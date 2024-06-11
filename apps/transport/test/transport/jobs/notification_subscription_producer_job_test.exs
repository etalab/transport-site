defmodule Transport.Test.Transport.Jobs.NotificationSubscriptionProducerJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.NotificationSubscriptionProducerJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "updates relevant notification subscriptions" do
    %DB.Contact{id: reuser_id} = insert_contact()

    %DB.Contact{id: producer_id} =
      insert_contact(%{
        organizations: [
          %{
            "acronym" => nil,
            "badges" => [],
            "id" => org_id = Ecto.UUID.generate(),
            "logo" => "https://example.com/original.png",
            "logo_thumbnail" => "https://example.com/100.png",
            "name" => "Big Corp",
            "slug" => "foo"
          }
        ]
      })

    %DB.Dataset{id: dataset_id} = insert(:dataset, organization_id: org_id)

    insert(:notification_subscription, %{
      reason: :expiration,
      source: :admin,
      dataset_id: dataset_id,
      contact_id: reuser_id,
      role: :reuser
    })

    # Should be deleted: the contact is a producer for this dataset and
    # the subscription's role is set to `reuser`.
    # We should create subscriptions for this (contact_id, dataset_id) for all
    # producer reasons
    insert(:notification_subscription, %{
      reason: :expiration,
      source: :admin,
      dataset_id: dataset_id,
      contact_id: producer_id,
      role: :reuser
    })

    # Should be left untouched: this is a platform-wide reason
    insert(:notification_subscription, %{
      reason: :new_dataset,
      source: :admin,
      dataset_id: nil,
      contact_id: producer_id,
      role: :reuser
    })

    assert :ok == perform_job(NotificationSubscriptionProducerJob, %{})

    assert [
             %DB.NotificationSubscription{
               reason: :expiration,
               source: :admin,
               role: :reuser,
               contact_id: ^reuser_id,
               dataset_id: ^dataset_id
             },
             %DB.NotificationSubscription{
               role: :producer,
               reason: :dataset_with_error,
               source: :"automation:migrate_from_reuser_to_producer",
               contact_id: ^producer_id,
               dataset_id: ^dataset_id
             },
             %DB.NotificationSubscription{
               reason: :expiration,
               source: :"automation:migrate_from_reuser_to_producer",
               role: :producer,
               contact_id: ^producer_id,
               dataset_id: ^dataset_id
             },
             %DB.NotificationSubscription{
               reason: :new_dataset,
               source: :admin,
               role: :reuser,
               contact_id: ^producer_id,
               dataset_id: nil
             },
             %DB.NotificationSubscription{
               reason: :resource_unavailable,
               source: :"automation:migrate_from_reuser_to_producer",
               role: :producer,
               contact_id: ^producer_id,
               dataset_id: ^dataset_id
             }
           ] =
             DB.NotificationSubscription |> DB.Repo.all() |> Enum.sort_by(&{&1.contact_id, &1.reason})
  end
end
