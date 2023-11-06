defmodule Transport.Test.Transport.Jobs.PeriodicReminderProducersNotificationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.PeriodicReminderProducersNotificationJob
  import Mox

  doctest PeriodicReminderProducersNotificationJob, import: true

  setup :verify_on_exit!

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
        source: :admin,
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

  test "other_contacts_in_orgs" do
    org_id = Ecto.UUID.generate()

    contact =
      insert_contact(%{
        organizations: [
          sample_org(%{"id" => org_id}),
          sample_org()
        ]
      })

    %DB.Contact{id: other_contact_id} =
      insert_contact(%{
        organizations: [
          sample_org(%{"id" => org_id})
        ]
      })

    assert [%DB.Contact{id: ^other_contact_id}] =
             PeriodicReminderProducersNotificationJob.other_contacts_in_orgs(contact)
  end

  test "other_producers_subscribers" do
    producer_1 = insert_contact()
    %DB.Contact{id: producer_2_id} = producer_2 = insert_contact()
    reuser = insert_contact()
    dataset = insert(:dataset)

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

    assert [%DB.Contact{id: ^producer_2_id}] =
             producer_1
             |> DB.Repo.preload(:notification_subscriptions)
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
    %DB.Contact{email: email} = producer_1 = insert_contact()
    producer_2 = insert_contact(%{first_name: "Marina", last_name: "Loiseau"})
    reuser = insert_contact()
    dataset = insert(:dataset, custom_title: "Super JDD")

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

    assert [%DB.Contact{id: ^admin_producer_id}] = PeriodicReminderProducersNotificationJob.admin_contacts()
    assert [admin_producer.id] == PeriodicReminderProducersNotificationJob.admin_contact_ids()

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.data.gouv.fr",
                             ^email = _to,
                             "contact@transport.data.gouv.fr",
                             subject,
                             "",
                             html ->
      assert subject == "Rappel : vos notifications pour vos données sur transport.data.gouv.fr"

      assert html =~
               ~s(Vous êtes susceptible de recevoir des notifications pour le jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~ "Les autres personnes inscrites à ces notifications sont : Marina Loiseau."
    end)

    assert :ok == perform_job(PeriodicReminderProducersNotificationJob, %{"contact_id" => producer_1.id})

    assert [%DB.Notification{reason: :periodic_reminder_producers, email: ^email}] = DB.Notification |> DB.Repo.all()
  end

  test "send mail to producer without subscriptions" do
    org_id = Ecto.UUID.generate()

    %DB.Contact{email: email} =
      contact =
      insert_contact(%{
        organizations: [
          sample_org(%{"id" => org_id})
        ]
      })

    insert_contact(%{
      first_name: "Marina",
      last_name: "Loiseau",
      organizations: [
        sample_org(%{"id" => org_id}),
        sample_org()
      ]
    })

    dataset = insert(:dataset, custom_title: "Super JDD", organization_id: org_id)

    refute contact
           |> DB.Repo.preload(:notification_subscriptions)
           |> PeriodicReminderProducersNotificationJob.subscribed_as_producer?()

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.data.gouv.fr",
                             ^email = _to,
                             "contact@transport.data.gouv.fr",
                             subject,
                             "",
                             html ->
      assert subject == "Notifications pour vos données sur transport.data.gouv.fr"

      assert html =~
               ~s(Vous gérez le jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~ "Pour vous faciliter la gestion de ces données, vous pouvez activer des notifications"

      assert html =~
               "Les autres personnes pouvant s’inscrire à ces notifications et s’étant déjà connectées sont : Marina Loiseau."
    end)

    assert :ok == perform_job(PeriodicReminderProducersNotificationJob, %{"contact_id" => contact.id})

    assert [%DB.Notification{reason: :periodic_reminder_producers, email: ^email}] = DB.Notification |> DB.Repo.all()
  end

  test "makes sure the email has not been sent recently already" do
    contact = insert_contact()
    refute PeriodicReminderProducersNotificationJob.sent_mail_recently?(contact)
    DB.Notification.insert!(:periodic_reminder_producers, contact.email)
    assert PeriodicReminderProducersNotificationJob.sent_mail_recently?(contact)

    assert {:discard, "Mail has already been sent recently"} ==
             perform_job(PeriodicReminderProducersNotificationJob, %{"contact_id" => contact.id})
  end

  describe "manage_organization_url" do
    test "single org" do
      org_id = Ecto.UUID.generate()
      contact = %{organizations: [sample_org(%{"id" => org_id})]} |> insert_contact() |> DB.Repo.preload(:organizations)
      assert 1 == contact.organizations |> Enum.count()

      assert "https://demo.data.gouv.fr/fr/admin/organization/#{org_id}/" ==
               contact |> PeriodicReminderProducersNotificationJob.manage_organization_url()
    end

    test "multiple orgs" do
      contact = %{organizations: [sample_org(), sample_org()]} |> insert_contact() |> DB.Repo.preload(:organizations)

      assert 2 == contact.organizations |> Enum.count()

      assert "https://demo.data.gouv.fr/fr/admin/" ==
               contact |> PeriodicReminderProducersNotificationJob.manage_organization_url()
    end
  end

  defp sample_org(%{} = args \\ %{}) do
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
