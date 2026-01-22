defmodule Transport.Test.Transport.Jobs.ExpirationNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.ExpirationNotificationJob

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  describe "dispatcher (main job)" do
    test "dispatches reuser digest jobs" do
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

      # Should have dispatched a reuser digest job for c2
      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.ExpirationNotificationJob",
                 args: %{"type" => "reuser_digest", "contact_id" => ^c2_id, "digest_date" => ^today_str},
                 conflict?: false,
                 state: "available"
               }
             ] = all_enqueued()
    end

    test "sends admin and producer notifications" do
      %DB.Dataset{id: dataset_id} =
        dataset =
        insert(:dataset, is_active: true, custom_title: "Dataset custom title", custom_tags: ["loi-climat-resilience"])

      assert DB.Dataset.climate_resilience_bill?(dataset)

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
               Date.utc_today() |> Transport.Expiration.datasets_with_resources_expiring_on()

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

      assert :ok == perform_job(ExpirationNotificationJob, %{}, inserted_at: DateTime.utc_now())

      # Admin email
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

      # Producer email
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

      # Notification logs
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
             ] = DB.Notification |> DB.Repo.all()
    end

    test "with nothing to send should not send email" do
      assert :ok == perform_job(ExpirationNotificationJob, %{}, inserted_at: DateTime.utc_now())
      assert_no_email_sent()
    end
  end

  describe "reuser digest worker" do
    test "sends digest email to reuser" do
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
               perform_job(
                 ExpirationNotificationJob,
                 %{type: "reuser_digest", contact_id: contact.id, digest_date: today},
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

    test "cannot dispatch the same reuser digest job twice for the same contact/date" do
      enqueue_job = fn ->
        %{type: "reuser_digest", contact_id: 42, digest_date: Date.utc_today()}
        |> ExpirationNotificationJob.new()
        |> Oban.insert!()
      end

      assert %Oban.Job{conflict?: false, unique: %{fields: [:args, :queue, :worker], period: 72_000}} = enqueue_job.()
      assert %Oban.Job{conflict?: true, unique: nil} = enqueue_job.()
    end
  end

  describe "gtfs_expiring_on_target_dates" do
    test "works with both GTFS validators" do
      today = Date.utc_today()
      a_week_ago = Date.add(today, -7)

      %{dataset: %DB.Dataset{id: d1_id}} = insert_resource_and_friends(today)

      %DB.Dataset{id: d2_id} = insert(:dataset)
      resource = insert(:resource, dataset_id: d2_id, format: "GTFS")
      resource_history = insert(:resource_history, resource: resource)

      insert(:multi_validation,
        resource_history: resource_history,
        validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
        metadata: %DB.ResourceMetadata{metadata: %{"start_date" => a_week_ago, "end_date" => a_week_ago}}
      )

      assert %{-7 => [d2_id], 0 => [d1_id]} == ExpirationNotificationJob.gtfs_expiring_on_target_dates(today)
    end
  end
end
