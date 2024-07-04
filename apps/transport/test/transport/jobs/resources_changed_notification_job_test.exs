defmodule Transport.Test.Transport.Jobs.ResourcesChangedNotificationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  import Swoosh.TestAssertions
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.ResourcesChangedNotificationJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "relevant_datasets and dispatches jobs" do
    today = DateTime.utc_now()
    today_date = today |> DateTime.to_date()
    yesterday = today |> DateTime.add(-1, :day)
    day_before = today |> DateTime.add(-2, :day)

    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    other_dataset = insert(:dataset)

    resource_dataset_gtfs =
      insert(:resource,
        dataset: dataset,
        format: "GTFS",
        url: "https://example.com/gtfs.zip",
        is_community_resource: false
      )

    resource_dataset_gtfs_rt =
      insert(:resource,
        dataset: dataset,
        format: "gtfs-rt",
        url: "https://example.com/gtfs-rt",
        is_community_resource: false
      )

    resource_other_dataset_gtfs =
      insert(:resource,
        dataset: other_dataset,
        format: "GTFS",
        is_community_resource: false,
        url: "https://example.fr/gtfs.zip"
      )

    community_resource_other_dataset =
      insert(:resource,
        dataset: other_dataset,
        format: "GTFS",
        is_community_resource: true,
        url: "https://lemonde.fr/pan"
      )

    resource_other_dataset_gtfs_rt =
      insert(:resource,
        dataset: other_dataset,
        format: "gtfs-rt",
        is_community_resource: false,
        url: "https://example.fr/gtfs.zip"
      )

    # `dataset` has a new resource today, `other_dataset` did not change today but before
    dataset_dh_today = insert(:dataset_history, dataset: dataset, inserted_at: today)
    dataset_dh_yesterday = insert(:dataset_history, dataset: dataset, inserted_at: yesterday)
    other_dataset_dh_today = insert(:dataset_history, dataset: other_dataset, inserted_at: today)
    other_dataset_dh_yesterday = insert(:dataset_history, dataset: other_dataset, inserted_at: yesterday)
    other_dataset_dh_day_before = insert(:dataset_history, dataset: other_dataset, inserted_at: day_before)

    # For `dataset`
    # Today: GTFS-RT + GTFS
    # Yesterday: GTFS
    insert(:dataset_history_resources,
      resource: resource_dataset_gtfs,
      payload: %{"download_url" => resource_dataset_gtfs.url},
      dataset_history: dataset_dh_today
    )

    insert(:dataset_history_resources,
      resource: resource_dataset_gtfs_rt,
      payload: %{"download_url" => resource_dataset_gtfs_rt.url},
      dataset_history: dataset_dh_today
    )

    insert(:dataset_history_resources,
      resource: resource_dataset_gtfs,
      payload: %{"download_url" => resource_dataset_gtfs.url},
      dataset_history: dataset_dh_yesterday
    )

    # For `other_dataset`
    # - 2 days ago: GTFS-RT + GTFS (should be ignored)
    # - Only a GTFS for yesterday and today
    # - A new community resource was added today (should be ignored)
    insert(:dataset_history_resources,
      resource: resource_other_dataset_gtfs,
      payload: %{"download_url" => resource_other_dataset_gtfs.url},
      dataset_history: other_dataset_dh_today
    )

    insert(:dataset_history_resources,
      resource: community_resource_other_dataset,
      payload: %{"download_url" => community_resource_other_dataset.url},
      dataset_history: other_dataset_dh_today
    )

    insert(:dataset_history_resources,
      resource: resource_other_dataset_gtfs,
      payload: %{"download_url" => resource_other_dataset_gtfs.url},
      dataset_history: other_dataset_dh_yesterday
    )

    insert(:dataset_history_resources,
      resource: resource_other_dataset_gtfs,
      payload: %{"download_url" => resource_other_dataset_gtfs.url},
      dataset_history: other_dataset_dh_day_before
    )

    insert(:dataset_history_resources,
      resource: resource_other_dataset_gtfs_rt,
      payload: %{"download_url" => resource_other_dataset_gtfs_rt.url},
      dataset_history: other_dataset_dh_day_before
    )

    assert [
             %{
               dataset_id: ^dataset_id,
               date: ^today_date,
               urls: "https://example.com/gtfs-rt,https://example.com/gtfs.zip"
             }
           ] = ResourcesChangedNotificationJob.relevant_datasets()

    assert :ok == perform_job(ResourcesChangedNotificationJob, %{})

    assert [%Oban.Job{worker: "Transport.Jobs.ResourcesChangedNotificationJob", args: %{"dataset_id" => ^dataset_id}}] =
             all_enqueued()
  end

  test "perform with a dataset_id" do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset, custom_title: "Super JDD")
    %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

    %DB.NotificationSubscription{id: ns_id} =
      insert(:notification_subscription, %{
        reason: :resources_changed,
        source: :admin,
        role: :reuser,
        contact_id: contact_id
      })

    assert :ok == perform_job(ResourcesChangedNotificationJob, %{"dataset_id" => dataset_id})

    # Logs have been saved
    assert [
             %DB.Notification{
               contact_id: ^contact_id,
               email: ^email,
               reason: :resources_changed,
               dataset_id: ^dataset_id,
               role: :reuser,
               notification_subscription_id: ^ns_id,
               payload: %{"job_id" => _}
             }
           ] = DB.Notification |> DB.Repo.all()

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: {DB.Contact.display_name(contact), email},
      reply_to: {"", "contact@transport.data.gouv.fr"},
      subject: "Super JDD : ressources modifiées",
      text_body: nil,
      html_body:
        ~r(Les ressources du jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> viennent d’être modifiées)
    )
  end
end
