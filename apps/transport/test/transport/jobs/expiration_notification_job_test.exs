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
    # - is a producer for a relevant expiration delay (+7). Producers have a distinct job but for all producers together
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
    # Does a single email
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
               args: %{"contact_id" => ^c2_id, "digest_date" => ^today_str, "role" => "reuser"},
               conflict?: false,
               state: "available"
             },
             %Oban.Job{
               worker: "Transport.Jobs.ExpirationNotificationJob",
               args: %{"role" => "admin_and_producer"},
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
             perform_job(ExpirationNotificationJob, %{contact_id: contact.id, digest_date: today, role: "reuser"},
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

  describe "admins and producer notifications" do
    test "sends email to our team + relevant contact before expiry" do
      %DB.Dataset{id: dataset_id} =
        dataset =
        insert(:dataset, is_active: true, custom_title: "Dataset custom title", custom_tags: ["loi-climat-resilience"])

      assert DB.Dataset.climate_resilience_bill?(dataset)
      # fake a resource expiring today
      %DB.Resource{id: resource_id} =
        resource = insert(:resource, dataset: dataset, format: "GTFS", title: resource_title = "Super GTFS")

      multi_validation =
        insert(:multi_validation,
          validator: Transport.Validators.GTFSTransport.validator_name(),
          resource_history: insert(:resource_history, resource: resource)
        )

      insert(:resource_metadata,
        multi_validation_id: multi_validation.id,
        metadata: %{"end_date" => Date.utc_today()}
      )

      assert [{%DB.Dataset{id: ^dataset_id}, [%DB.Resource{id: ^resource_id}]}] =
               Date.utc_today() |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

      %DB.NotificationSubscription{id: ns_id} =
        insert(:notification_subscription, %{
          reason: :expiration,
          source: :admin,
          role: :producer,
          contact_id: contact_id,
          dataset_id: dataset.id
        })

      # Should be ignored, this subscription is for a reuser
      %DB.Contact{id: reuser_id} = insert_contact()

      insert(:notification_subscription, %{
        reason: :expiration,
        source: :user,
        role: :reuser,
        contact_id: reuser_id,
        dataset_id: dataset.id
      })

      assert :ok == perform_job(Transport.Jobs.ExpirationNotificationJob, %{"role" => "admin_and_producer"})

      # a first mail to our team

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{"", "contact@transport.data.gouv.fr"}],
                             subject: "Jeux de données arrivant à expiration",
                             text_body: nil,
                             html_body: body
                           } ->
        assert body =~ ~r/Jeux de données périmant demain :/

        assert body =~
                 ~s|<li><a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> - ✅ notification automatique ⚖️🗺️ article 122</li>|
      end)

      # a second mail to the email address in the notifications config
      display_name = DB.Contact.display_name(contact)

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{^display_name, ^email}],
                             subject: "Jeu de données arrivant à expiration",
                             html_body: html_body
                           } ->
        refute html_body =~ "notification automatique"
        refute html_body =~ "article 122"

        assert html_body =~
                 ~s(Les données GTFS #{resource_title} associées au jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> périment demain.)

        assert html_body =~
                 ~s(<a href="https://doc.transport.data.gouv.fr/administration-des-donnees/procedures-de-publication/mettre-a-jour-des-donnees#remplacer-un-jeu-de-donnees-existant-plutot-quen-creer-un-nouveau">remplaçant la ressource périmée par la nouvelle</a>)
      end)

      # Logs are there
      assert [
               %DB.Notification{
                 contact_id: ^contact_id,
                 email: ^email,
                 reason: :expiration,
                 dataset_id: ^dataset_id,
                 notification_subscription_id: ^ns_id,
                 role: :producer,
                 payload: %{"delay" => 0, "job_id" => _job_id}
               }
             ] =
               DB.Notification |> DB.Repo.all()
    end

    test "outdated_data job with nothing to send should not send email" do
      assert :ok == perform_job(Transport.Jobs.ExpirationNotificationJob, %{"role" => "admin_and_producer"})
      assert_no_email_sent()
    end

    test "gtfs_datasets_expiring_on" do
      {today, tomorrow, yesterday} = {Date.utc_today(), Date.add(Date.utc_today(), 1), Date.add(Date.utc_today(), -1)}
      assert [] == today |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      insert_fn = fn %Date{} = expiration_date, %DB.Dataset{} = dataset ->
        multi_validation =
          insert(:multi_validation,
            validator: Transport.Validators.GTFSTransport.validator_name(),
            resource_history: insert(:resource_history, resource: insert(:resource, dataset: dataset, format: "GTFS"))
          )

        insert(:resource_metadata,
          multi_validation_id: multi_validation.id,
          metadata: %{"end_date" => expiration_date}
        )
      end

      # Ignores hidden or inactive datasets
      insert_fn.(today, insert(:dataset, is_active: false))
      insert_fn.(today, insert(:dataset, is_active: true, is_hidden: true))

      assert [] == today |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      # 2 GTFS resources expiring on the same day for a dataset
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset, is_active: true)
      insert_fn.(today, dataset)
      insert_fn.(today, dataset)

      assert [
               {%DB.Dataset{id: ^dataset_id},
                [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
             ] = today |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      assert [] == tomorrow |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()
      assert [] == yesterday |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      insert_fn.(tomorrow, dataset)

      assert [
               {%DB.Dataset{id: ^dataset_id},
                [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
             ] = today |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      assert [
               {%DB.Dataset{id: ^dataset_id}, [%DB.Resource{dataset_id: ^dataset_id}]}
             ] = tomorrow |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      assert [] == yesterday |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()

      # Multiple datasets
      %DB.Dataset{id: d2_id} = d2 = insert(:dataset, is_active: true)
      insert_fn.(today, d2)

      assert [
               {%DB.Dataset{id: ^dataset_id},
                [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]},
               {%DB.Dataset{id: ^d2_id}, [%DB.Resource{dataset_id: ^d2_id}]}
             ] = today |> Transport.Jobs.ExpirationNotificationJob.gtfs_datasets_expiring_on()
    end
  end
end
