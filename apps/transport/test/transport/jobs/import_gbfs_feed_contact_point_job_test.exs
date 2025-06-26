defmodule Transport.Test.Transport.Jobs.ImportGBFSFeedContactEmailJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ImportGBFSFeedContactEmailJob
  doctest ImportGBFSFeedContactEmailJob, import: true

  @producer_reasons Transport.NotificationReason.subscribable_reasons_related_to_datasets(:producer) |> MapSet.new()

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "gbfs_feed_contact_emails" do
    gbfs_1 = insert(:resource, format: "gbfs")
    gbfs_2 = insert(:resource, format: "gbfs")
    gbfs_3 = insert(:resource, format: "gbfs")
    gbfs_4 = insert(:resource, format: "gbfs")

    ten_days_ago = DateTime.utc_now() |> DateTime.add(-10, :day)
    five_days_ago = DateTime.utc_now() |> DateTime.add(-5, :day)

    # `gbfs_1` is relevant but should not be duplicated
    insert(:resource_metadata,
      resource_id: gbfs_1.id,
      metadata: %{system_details: %{feed_contact_email: "gbfs1_old@example.com"}},
      inserted_at: five_days_ago
    )

    insert(:resource_metadata,
      resource_id: gbfs_1.id,
      metadata: %{system_details: %{feed_contact_email: gbfs_1_email = "gbfs1@example.com"}}
    )

    insert(:resource_metadata,
      resource_id: gbfs_1.id,
      metadata: %{system_details: %{feed_contact_email: gbfs_1_email}}
    )

    # `gbfs_4` should be included
    insert(:resource_metadata,
      resource_id: gbfs_4.id,
      metadata: %{system_details: %{feed_contact_email: gbfs_4_email = "gbfs4@example.com"}}
    )

    # Ignored: too old
    insert(:resource_metadata,
      resource_id: gbfs_2.id,
      metadata: %{system_details: %{feed_contact_email: "gbfs2@example.com"}},
      inserted_at: ten_days_ago
    )

    # Ignored: no feed_contact_email
    insert(:resource_metadata,
      resource_id: gbfs_3.id,
      metadata: %{system_details: %{foo: 42}},
      inserted_at: five_days_ago
    )

    result = ImportGBFSFeedContactEmailJob.gbfs_feed_contact_emails()
    assert Enum.count(result) == 2

    assert [
             %{
               resource_id: gbfs_1.id,
               feed_contact_email: gbfs_1_email,
               dataset_id: gbfs_1.dataset_id,
               resource_url: gbfs_1.url
             },
             %{
               resource_id: gbfs_4.id,
               feed_contact_email: gbfs_4_email,
               dataset_id: gbfs_4.dataset_id,
               resource_url: gbfs_4.url
             }
           ]
           |> MapSet.new() == MapSet.new(result)
  end

  describe "update_feed_contact_email" do
    test "creates producer subscriptions for an existing contact with a subscription" do
      %DB.Contact{id: contact_id} = gbfs_contact = insert_contact()
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)

      insert(:notification_subscription,
        dataset_id: dataset.id,
        contact_id: gbfs_contact.id,
        role: :producer,
        reason: :expiration,
        source: :user
      )

      ImportGBFSFeedContactEmailJob.update_feed_contact_email(%{
        resource_url: "https://example.com/gbfs.json",
        dataset_id: dataset_id,
        feed_contact_email: gbfs_contact.email
      })

      assert @producer_reasons ==
               DB.NotificationSubscription.base_query()
               |> where(
                 [notification_subscription: ns],
                 ns.dataset_id == ^dataset_id and ns.role == :producer and ns.contact_id == ^contact_id
               )
               |> select([notification_subscription: ns], ns.reason)
               |> DB.Repo.all()
               |> MapSet.new()

      # Kept the already existing subscription made by the user (`source: :user`) and created
      # the remaining producer reasons.
      assert [
               %{count: Enum.count(@producer_reasons) - 1, source: :"automation:gbfs_feed_contact_email"},
               %{count: 1, source: :user}
             ] ==
               DB.NotificationSubscription.base_query()
               |> where(
                 [notification_subscription: ns],
                 ns.dataset_id == ^dataset_id and ns.role == :producer and ns.contact_id == ^contact_id
               )
               |> select([notification_subscription: ns], %{source: ns.source, count: count(ns.id)})
               |> group_by([notification_subscription: ns], ns.source)
               |> DB.Repo.all()
    end

    test "creates a new contact and producer subscriptions, deletes the previous GBFS contact subscriptions" do
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
      previous_gbfs_contact = insert_contact()
      email = "john@example.fr"

      previous_gbfs_contact_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: previous_gbfs_contact.id,
          role: :producer,
          reason: :expiration,
          source: :"automation:gbfs_feed_contact_email"
        )

      ImportGBFSFeedContactEmailJob.update_feed_contact_email(%{
        resource_url: "https://example.com/gbfs.json",
        dataset_id: dataset_id,
        feed_contact_email: email
      })

      %DB.Contact{email: ^email, creation_source: :"automation:import_gbfs_feed_contact_email", organization: "Example"} =
        contact = DB.Repo.get_by(DB.Contact, mailing_list_title: "Équipe technique GBFS Example")

      assert nil == DB.Repo.reload(previous_gbfs_contact_ns)
      assert MapSet.new([]) == subscribed_reasons(dataset, previous_gbfs_contact)
      assert @producer_reasons == subscribed_reasons(dataset, contact)
    end

    test "does nothing if the subscriptions are already in place, for another source" do
      gbfs_contact = insert_contact()
      other_producer = insert_contact()
      dataset = insert(:dataset)

      subscriptions =
        Enum.map(@producer_reasons, fn reason ->
          insert(:notification_subscription,
            dataset_id: dataset.id,
            contact_id: gbfs_contact.id,
            role: :producer,
            reason: reason,
            source: :user
          )
        end)

      # Another producer's subscription does not interfere
      other_ns =
        insert(:notification_subscription,
          dataset_id: dataset.id,
          contact_id: other_producer.id,
          role: :producer,
          reason: :expiration,
          source: :user
        )

      ImportGBFSFeedContactEmailJob.update_feed_contact_email(%{
        resource_url: "https://example.com/gbfs.json",
        dataset_id: dataset.id,
        feed_contact_email: gbfs_contact.email
      })

      # Subscriptions are still there and did not change
      assert other_ns == DB.Repo.reload(other_ns)
      assert subscriptions == DB.Repo.reload(subscriptions)
    end
  end

  test "perform" do
    gbfs_1 = insert(:resource, dataset: insert(:dataset), format: "gbfs", url: "https://example.com/gbfs.json")
    gbfs_2 = insert(:resource, dataset: insert(:dataset), format: "gbfs")
    %DB.Contact{id: existing_gbfs_contact_id, email: gbfs_2_email} = existing_gbfs_contact = insert_contact()

    five_days_ago = DateTime.utc_now() |> DateTime.add(-5, :day)

    insert(:resource_metadata,
      resource_id: gbfs_1.id,
      metadata: %{system_details: %{feed_contact_email: gbfs_1_email = "gbfs1@example.com"}},
      inserted_at: five_days_ago
    )

    insert(:resource_metadata,
      resource_id: gbfs_2.id,
      metadata: %{system_details: %{feed_contact_email: gbfs_2_email}}
    )

    assert :ok == perform_job(ImportGBFSFeedContactEmailJob, %{})

    assert [first_contact, new_contact] = DB.Contact |> DB.Repo.all() |> Enum.sort_by(& &1.id)

    assert %DB.Contact{id: ^existing_gbfs_contact_id, email: ^gbfs_2_email} = first_contact
    assert "Example" == Transport.GBFSMetadata.operator(gbfs_1.url)
    assert %DB.Contact{email: ^gbfs_1_email, mailing_list_title: "Équipe technique GBFS Example"} = new_contact

    # Subscriptions have been created:
    # - `new_contact` for `gbfs_1`'s dataset only
    # - `existing_gbfs_contact` for `gbfs_2`'s dataset only
    assert @producer_reasons == subscribed_reasons(%DB.Dataset{id: gbfs_1.dataset_id}, new_contact)
    assert MapSet.new([]) == subscribed_reasons(%DB.Dataset{id: gbfs_2.dataset_id}, new_contact)

    assert MapSet.new([]) == subscribed_reasons(%DB.Dataset{id: gbfs_1.dataset_id}, existing_gbfs_contact)
    assert @producer_reasons == subscribed_reasons(%DB.Dataset{id: gbfs_2.dataset_id}, existing_gbfs_contact)
  end

  defp subscribed_reasons(%DB.Dataset{id: dataset_id}, %DB.Contact{id: contact_id}) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.dataset_id == ^dataset_id and ns.role == :producer and ns.contact_id == ^contact_id and
        ns.source == :"automation:gbfs_feed_contact_email"
    )
    |> select([notification_subscription: ns], ns.reason)
    |> DB.Repo.all()
    |> MapSet.new()
  end
end
