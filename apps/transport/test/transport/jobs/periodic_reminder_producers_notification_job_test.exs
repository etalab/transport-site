defmodule Transport.Test.Transport.Jobs.PeriodicReminderProducersNotificationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.PeriodicReminderProducersNotificationJob
  import Swoosh.TestAssertions

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
      insert(:dataset, organization_id: publisher_org_id = Ecto.UUID.generate())
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
        source: :user,
        role: :reuser,
        reason: :expiration,
        dataset: dataset,
        contact: insert_contact()
      )

      # Contact should be kept: no subscriptions but member of orgs
      # with published datasets.
      # A single job should be enqueued even if the contact is a member
      # of multiple orgs with published datasets.
      %DB.Contact{id: contact_id_with_org} =
        insert_contact(%{
          organizations: [
            sample_org(%{"id" => org_id}),
            sample_org(%{"id" => publisher_org_id})
          ]
        })

      assert 1 == PeriodicReminderProducersNotificationJob.chunk_size()

      assert :ok ==
               perform_job(PeriodicReminderProducersNotificationJob, %{}, inserted_at: ~U[2023-07-03 09:00:00.000000Z])

      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.PeriodicReminderProducersNotificationJob",
                 args: %{"contact_id" => ^contact_id_without_org},
                 scheduled_at: ~U[2023-07-04 09:00:00.000000Z],
                 state: "scheduled"
               },
               %Oban.Job{
                 worker: "Transport.Jobs.PeriodicReminderProducersNotificationJob",
                 args: %{"contact_id" => ^contact_id_with_org},
                 scheduled_at: ~U[2023-07-03 09:00:00.000000Z],
                 state: "scheduled"
               }
             ] = all_enqueued()
    end
  end

  test "subscribed_as_producer?" do
    dataset = insert(:dataset)
    contact = insert_contact()

    insert(:notification_subscription,
      source: :admin,
      role: :reuser,
      reason: :new_dataset,
      contact: contact
    )

    refute contact
           |> DB.Repo.preload(:notification_subscriptions)
           |> PeriodicReminderProducersNotificationJob.subscribed_as_producer?()

    insert(:notification_subscription,
      source: :admin,
      role: :producer,
      reason: :expiration,
      dataset: dataset,
      contact: contact
    )

    assert contact
           |> DB.Repo.preload(:notification_subscriptions)
           |> PeriodicReminderProducersNotificationJob.subscribed_as_producer?()
  end

  test "other_producers_subscribers" do
    producer_1 = insert_contact()
    %DB.Contact{id: producer_2_id} = producer_2 = insert_contact()
    reuser = insert_contact()
    dataset = insert(:dataset)
    other_dataset = insert(:dataset)

    # Should be ignored, the contact of a member of the transport.data.gouv.fr's org
    admin_producer =
      insert_contact(%{organizations: [sample_org(%{"name" => "Point d'Accès National transport.data.gouv.fr"})]})

    [{producer_1, :producer}, {producer_2, :producer}, {reuser, :reuser}, {admin_producer, :producer}]
    |> Enum.each(fn {%DB.Contact{} = contact, role} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :expiration,
        dataset: dataset,
        contact: contact
      )
    end)

    # Subscribed as a reuser to another dataset and a producer has notifications enabled.
    # Should not list the other producer.
    [{producer_1, :reuser}, {producer_2, :producer}]
    |> Enum.each(fn {%DB.Contact{} = current_contact, role} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :expiration,
        dataset: other_dataset,
        contact: current_contact
      )
    end)

    assert [%DB.Contact{id: ^producer_2_id}] =
             producer_1
             |> DB.Repo.preload(notification_subscriptions: [:dataset])
             |> PeriodicReminderProducersNotificationJob.other_producers_subscribers()
  end

  test "datasets_subscribed_as_producer" do
    contact = insert_contact()
    %DB.Dataset{id: d1_id} = d1 = insert(:dataset, custom_title: "A")
    %DB.Dataset{id: d2_id} = d2 = insert(:dataset, custom_title: "B")
    d3 = insert(:dataset, custom_title: "C")

    [
      {d1, :producer, :expiration},
      {d2, :producer, :expiration},
      {d2, :producer, :dataset_with_error},
      {d3, :reuser, :expiration}
    ]
    |> Enum.each(fn {%DB.Dataset{} = dataset, role, reason} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: reason,
        dataset: dataset,
        contact: contact
      )
    end)

    assert [%DB.Dataset{id: ^d1_id}, %DB.Dataset{id: ^d2_id}] =
             contact
             |> DB.Repo.preload(notification_subscriptions: [:dataset])
             |> PeriodicReminderProducersNotificationJob.datasets_subscribed_as_producer()
  end

  test "send mail to producer with subscriptions" do
    %DB.Contact{id: contact_id, email: email} = producer_1 = insert_contact()
    producer_2 = insert_contact(%{first_name: "Marina", last_name: "Loiseau"})
    producer_3 = insert_contact(%{first_name: "Foo", last_name: "Baz"})
    reuser = insert_contact()
    dataset = insert(:dataset, custom_title: "Super JDD")
    other_dataset = insert(:dataset)

    %DB.Contact{id: admin_producer_id} =
      admin_producer =
      insert_contact(%{organizations: [sample_org(%{"name" => "Point d'Accès National transport.data.gouv.fr"})]})

    [{producer_1, :producer}, {producer_2, :producer}, {reuser, :reuser}, {admin_producer, :producer}]
    |> Enum.each(fn {%DB.Contact{} = contact, role} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :expiration,
        dataset: dataset,
        contact: contact
      )
    end)

    # Subscribed as a reuser to another dataset and a producer has notifications enabled.
    # Should not list the other producer.
    [{producer_1, :reuser}, {producer_3, :producer}]
    |> Enum.each(fn {%DB.Contact{} = contact, role} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :expiration,
        dataset: other_dataset,
        contact: contact
      )
    end)

    assert [%DB.Contact{id: ^admin_producer_id}] = DB.Contact.admin_contacts()
    assert [admin_producer.id] == DB.Contact.admin_contact_ids()

    assert :ok == perform_job(PeriodicReminderProducersNotificationJob, %{"contact_id" => producer_1.id})

    display_name = DB.Contact.display_name(producer_1)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, ^email}],
                           subject: subject,
                           html_body: html
                         } ->
      assert subject == "Rappel : vos notifications pour vos données sur transport.data.gouv.fr"

      assert html =~
               ~s(Vous êtes inscrit à des notifications pour le jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~ "Les autres personnes inscrites à ces notifications sont : Marina Loiseau."
    end)

    assert [
             %DB.Notification{
               reason: :periodic_reminder_producers,
               email: ^email,
               contact_id: ^contact_id,
               dataset_id: nil,
               role: :producer,
               payload: %{"template_type" => "producer_with_subscriptions"},
               notification_subscription_id: nil
             }
           ] = DB.Notification |> DB.Repo.all()
  end

  test "send mail to producer without subscriptions" do
    org_id = Ecto.UUID.generate()

    %DB.Contact{id: contact_id, email: email} =
      contact =
      insert_contact(%{
        organizations: [
          sample_org(%{"id" => org_id})
        ]
      })

    dataset = insert(:dataset, custom_title: "Super JDD", organization_id: org_id)

    refute contact
           |> DB.Repo.preload(:notification_subscriptions)
           |> PeriodicReminderProducersNotificationJob.subscribed_as_producer?()

    assert :ok == perform_job(PeriodicReminderProducersNotificationJob, %{"contact_id" => contact.id})

    display_name = DB.Contact.display_name(contact)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, ^email}],
                           subject: subject,
                           html_body: html
                         } ->
      assert subject == "Notifications pour vos données sur transport.data.gouv.fr"

      assert html =~
               ~s(Il est possible de vous inscrire à des notifications concernant le jeu de données que vous gérez sur transport.data.gouv.fr, <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~
               ~s(Pour vous inscrire, rien de plus simple : rendez-vous sur votre <a href="http://127.0.0.1:5100/espace_producteur?utm_source=transactional_email&amp;utm_medium=email&amp;utm_campaign=periodic_reminder_producer_without_subscriptions">Espace Producteur</a>)
    end)

    assert [
             %DB.Notification{
               reason: :periodic_reminder_producers,
               email: ^email,
               contact_id: ^contact_id,
               dataset_id: nil,
               role: :producer,
               payload: %{"template_type" => "producer_without_subscriptions"},
               notification_subscription_id: nil
             }
           ] = DB.Notification |> DB.Repo.all()
  end

  test "makes sure the email has not been sent recently already" do
    contact = insert_contact()
    refute PeriodicReminderProducersNotificationJob.sent_mail_recently?(contact)

    insert_notification(%{
      email: contact.email,
      reason: DB.NotificationSubscription.reason(:periodic_reminder_producers),
      role: :producer
    })

    assert PeriodicReminderProducersNotificationJob.sent_mail_recently?(contact)

    assert {:discard, "Mail has already been sent recently"} ==
             perform_job(PeriodicReminderProducersNotificationJob, %{"contact_id" => contact.id})
  end

  defp sample_org(%{} = args) do
    Map.merge(
      %{
        "acronym" => nil,
        "badges" => [],
        "id" => Ecto.UUID.generate(),
        "logo" => "https://example.com/original.png",
        "logo_thumbnail" => "https://example.com/100.png",
        "name" => "Big Corp",
        "slug" => "foo" <> Ecto.UUID.generate()
      },
      args
    )
  end
end
