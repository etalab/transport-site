defmodule Transport.Test.Transport.Jobs.PeriodicReminderProducersNotificationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  # import Ecto.Query
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
            sample_org(%{"id" => org_id})
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

  test "all_orgs" do
    dataset = insert(:dataset, organization_id: dataset_org_id = Ecto.UUID.generate())

    contact =
      insert_contact(%{
        organizations: [
          sample_org(%{"id" => org_id = Ecto.UUID.generate()})
        ]
      })

    Enum.each(~w(expiration dataset_with_error), fn reason ->
      insert(:notification_subscription,
        source: :admin,
        role: :producer,
        reason: reason,
        dataset: dataset,
        contact: contact
      )
    end)

    assert [dataset_org_id, org_id] |> Enum.sort() ==
             contact
             |> DB.Repo.preload([:organizations, notification_subscriptions: [:dataset]])
             |> PeriodicReminderProducersNotificationJob.all_orgs()
             |> Enum.sort()
  end

  test "contacts_in_orgs" do
    dataset = insert(:dataset, organization_id: dataset_org_id = Ecto.UUID.generate())
    contact_with_sub = insert_contact()

    insert(:notification_subscription,
      source: :admin,
      role: :producer,
      reason: :expiration,
      dataset: dataset,
      contact: contact_with_sub
    )

    %DB.Contact{id: contact_without_subs_id} =
      insert_contact(%{
        organizations: [
          sample_org(%{"id" => dataset_org_id})
        ]
      })

    assert [%DB.Contact{id: ^contact_without_subs_id}] =
             PeriodicReminderProducersNotificationJob.contacts_in_orgs([dataset_org_id, Ecto.UUID.generate()])
  end

  test "other_producers_subscribers" do
    producer_1 = insert_contact()
    %DB.Contact{id: producer_2_id} = producer_2 = insert_contact()
    reuser = insert_contact()
    dataset = insert(:dataset)

    [{producer_1, :producer}, {producer_2, :producer}, {reuser, :reuser}]
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

  test "send mail to producer with subscriptions" do
    %DB.Contact{email: email} = producer_1 = insert_contact()
    producer_2 = insert_contact(%{first_name: "Marina", last_name: "Loiseau"})
    reuser = insert_contact()
    dataset = insert(:dataset, custom_title: "Super JDD")

    [{producer_1, :producer}, {producer_2, :producer}, {reuser, :reuser}]
    |> Enum.each(fn {%DB.Contact{} = contact, role} ->
      insert(:notification_subscription,
        source: :admin,
        role: role,
        reason: :expiration,
        dataset: dataset,
        contact: contact
      )
    end)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email = _to,
                             "contact@transport.beta.gouv.fr",
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

  defp sample_org(%{} = args) do
    Map.merge(
      %{
        "acronym" => nil,
        "badges" => [],
        "id" => Ecto.UUID.generate(),
        "logo" => "https://example.com/original.png",
        "logo_thumbnail" => "https://example.com/100.png",
        "name" => "Big Corp",
        "slug" => "foo"
      },
      args
    )
  end
end
