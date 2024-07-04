defmodule Transport.Test.Transport.Jobs.ExpirationNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.ExpirationNotificationJob

  doctest ExpirationNotificationJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform: dispatches other jobs" do
    today = Date.utc_today()
    today_str = today |> Date.to_string()
    a_week_ago = Date.add(today, -7)
    yesterday = Date.add(today, -1)
    a_week_from_now = Date.add(today, 7)

    # 2 resources expiring on the same date, does not include the dataset twice
    %{dataset: %DB.Dataset{} = d1} = insert_resource_and_friends(today)
    insert_resource_and_friends(today, dataset: d1)
    %{dataset: %DB.Dataset{} = d2} = insert_resource_and_friends(yesterday)
    %{dataset: %DB.Dataset{} = d3} = insert_resource_and_friends(a_week_ago)
    %{dataset: %DB.Dataset{} = d4} = insert_resource_and_friends(a_week_from_now)

    %DB.Contact{} = c1 = insert_contact()
    %DB.Contact{id: c2_id} = c2 = insert_contact()

    # Subscriptions for `c1`: should not match because:
    # - is a producer for a relevant expiration delay (+7)
    # - is a reuser but for an ignored expiration delay
    # - is a reuser for an irrelevant reason for a matching dataset
    insert(:notification_subscription,
      contact_id: c1.id,
      dataset_id: d1.id,
      reason: :dataset_with_error,
      role: :reuser,
      source: :user
    )

    insert(:notification_subscription,
      contact_id: c1.id,
      dataset_id: d2.id,
      reason: :expiration,
      role: :reuser,
      source: :user
    )

    insert(:notification_subscription,
      contact_id: c1.id,
      dataset_id: d4.id,
      reason: :expiration,
      role: :producer,
      source: :user
    )

    # Subscriptions for `c2`: matches for expiration today and for +7
    insert(:notification_subscription,
      contact_id: c2.id,
      dataset_id: d1.id,
      reason: :expiration,
      role: :reuser,
      source: :user
    )

    insert(:notification_subscription,
      contact_id: c2.id,
      dataset_id: d4.id,
      reason: :expiration,
      role: :reuser,
      source: :user
    )

    assert %{-7 => [d3.id], 0 => [d1.id], 7 => [d4.id]} ==
             ExpirationNotificationJob.gtfs_expiring_on_target_dates(today)

    assert :ok == perform_job(ExpirationNotificationJob, %{}, inserted_at: DateTime.utc_now())

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.ExpirationNotificationJob",
               args: %{"contact_id" => ^c2_id, "digest_date" => ^today_str},
               conflict?: false,
               state: "available"
             }
           ] = all_enqueued()
  end

  test "perform for a specific contact_id" do
    today = Date.utc_today()
    a_week_ago = Date.add(today, -7)
    yesterday = Date.add(today, -1)
    a_week_from_now = Date.add(today, 7)
    # 2 resources expiring on the same date, does not include the dataset twice
    %{dataset: %DB.Dataset{id: d1_id} = d1} = insert_resource_and_friends(today)
    insert_resource_and_friends(today, dataset: d1)
    %{dataset: %DB.Dataset{} = d2} = insert_resource_and_friends(yesterday)
    %{dataset: %DB.Dataset{} = d3} = insert_resource_and_friends(a_week_ago)
    %{dataset: %DB.Dataset{id: d4_id} = d4} = insert_resource_and_friends(a_week_from_now)

    %DB.Contact{id: contact_id, email: contact_email} = contact = insert_contact()

    %DB.NotificationSubscription{id: ns1_id} =
      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: d1.id,
        reason: :expiration,
        role: :reuser,
        source: :user
      )

    insert(:notification_subscription,
      contact_id: contact.id,
      dataset_id: d2.id,
      reason: :expiration,
      role: :reuser,
      source: :user
    )

    %DB.NotificationSubscription{id: ns4_id} =
      insert(:notification_subscription,
        contact_id: contact.id,
        dataset_id: d4.id,
        reason: :expiration,
        role: :reuser,
        source: :user
      )

    assert %{-7 => [d3.id], 0 => [d1.id], 7 => [d4.id]} ==
             ExpirationNotificationJob.gtfs_expiring_on_target_dates(today)

    assert :ok ==
             perform_job(ExpirationNotificationJob, %{contact_id: contact.id, digest_date: today},
               inserted_at: DateTime.utc_now()
             )

    display_name = DB.Contact.display_name(contact)

    assert_email_sent(fn %Swoosh.Email{
                           subject: "Suivi des jeux de données favoris arrivant à expiration",
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, ^contact_email}],
                           text_body: nil,
                           html_body: html
                         } ->
      html = String.replace(html, "\n", "")

      assert html =~
               ~s|<p>Bonjour,</p><p>Voici un résumé de vos jeux de données favoris arrivant à expiration.</p><strong>Jeux de données périmant demain :</strong><ul><li><a href="http://127.0.0.1:5100/datasets/#{d1.slug}">Hello</a></li></ul><br/><strong>Jeux de données périmant dans 7 jours :</strong><ul><li><a href="http://127.0.0.1:5100/datasets/#{d4.slug}">Hello</a></li></ul>|

      assert html =~
               ~s|vous pouvez paramétrer vos alertes sur le suivi de vos jeux de données favoris depuis votre <a href="http://127.0.0.1:5100/espace_reutilisateur?utm_source=transactional_email&amp;utm_medium=email&amp;utm_campaign=expiration_reuser">Espace réutilisateur</a>|
    end)

    assert [
             %DB.Notification{
               reason: :expiration,
               role: :reuser,
               email: ^contact_email,
               contact_id: ^contact_id,
               dataset_id: ^d1_id,
               notification_subscription_id: ^ns1_id,
               payload: %{"job_id" => job_id1}
             },
             %DB.Notification{
               reason: :expiration,
               role: :reuser,
               email: ^contact_email,
               contact_id: ^contact_id,
               dataset_id: ^d4_id,
               notification_subscription_id: ^ns4_id,
               payload: %{"job_id" => job_id2}
             }
           ] = DB.Notification |> DB.Repo.all() |> Enum.sort_by(& &1.dataset_id)

    assert [job_id1, job_id2] |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.count() == 1
  end

  test "cannot dispatch the same job twice for the same contact/date" do
    enqueue_job = fn ->
      %{contact_id: 42, digest_date: Date.utc_today()} |> ExpirationNotificationJob.new() |> Oban.insert!()
    end

    assert %Oban.Job{conflict?: false, unique: %{fields: [:args, :queue, :worker], period: 72_000}} = enqueue_job.()
    assert %Oban.Job{conflict?: true, unique: nil} = enqueue_job.()
  end
end
