defmodule Transport.Test.Transport.Jobs.NotificationSubscriptionProducerJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.NotificationSubscriptionProducerJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "updates relevant notification subscriptions" do
    reuser = insert_contact()

    producer =
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

    dataset = insert(:dataset, organization_id: org_id)

    ns_reuser =
      insert(:notification_subscription, %{
        reason: :expiration,
        source: :admin,
        dataset_id: dataset.id,
        contact_id: reuser.id,
        role: :reuser
      })

    # Should be updated: the contact is a producer for this dataset and
    # the subscription's role is set to `reuser`
    ns_producer =
      insert(:notification_subscription, %{
        reason: :expiration,
        source: :admin,
        dataset_id: dataset.id,
        contact_id: producer.id,
        role: :reuser
      })

    assert :ok == perform_job(NotificationSubscriptionProducerJob, %{})

    assert [%DB.NotificationSubscription{role: :reuser}, %DB.NotificationSubscription{role: :producer}] =
             DB.Repo.reload!([ns_reuser, ns_producer])
  end
end
