defmodule Transport.Test.Transport.Jobs.ResourceUnavailableNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  import Swoosh.TestAssertions
  alias Transport.Jobs.ResourceUnavailableNotificationJob

  setup :verify_on_exit!

  setup do
    # Using the real implementation for the moment, then it falls back on `HTTPoison.Mock`
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

  test "relevant_unavailabilities" do
    dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)
    gtfs_resource = insert(:resource, dataset: dataset, format: "GTFS")

    other_dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)
    geojson_resource = insert(:resource, dataset: other_dataset, format: "geojson")

    assert [] == ResourceUnavailableNotificationJob.relevant_unavailabilities(DateTime.utc_now())

    insert(:resource_unavailability,
      start: DateTime.add(DateTime.utc_now(), -6 * 60 - 15, :minute),
      end: nil,
      resource_id: gtfs_resource.id
    )

    # Ignored because it's ongoing but started 7 hours ago
    insert(:resource_unavailability,
      start: DateTime.add(DateTime.utc_now(), -7, :hour),
      end: nil,
      resource_id: geojson_resource.id
    )

    assert [dataset.id] ==
             DateTime.utc_now()
             |> ResourceUnavailableNotificationJob.relevant_unavailabilities()
             |> Enum.map(&elem(&1, 0).id)
  end

  test "perform" do
    # 2 datasets in scope: 1 GTFS dataset with a resource, another dataset with 2 resources
    # All resources are currently down for [6h00 ; 6h30]
    %{id: dataset_id} = dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")

    %{id: gtfs_dataset_id} =
      gtfs_dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Dataset GTFS")

    %DB.Resource{id: resource_1_id} =
      resource_1 =
      insert(:resource,
        dataset: dataset,
        format: "geojson",
        title: "GeoJSON 1",
        url: "https://static.data.gouv.fr/file.geojson"
      )

    %DB.Resource{id: resource_2_id} =
      resource_2 =
      insert(:resource,
        dataset: dataset,
        format: "geojson",
        title: "GeoJSON 2",
        url: "https://static.data.gouv.fr/other_file.geojson"
      )

    %DB.Resource{id: resource_gtfs_id} =
      resource_gtfs = insert(:resource, dataset: gtfs_dataset, format: "GTFS", url: "https://example/file.zip")

    insert(:resource_unavailability,
      start: DateTime.add(DateTime.utc_now(), -6 * 60 - 29, :minute),
      end: nil,
      resource_id: resource_1.id
    )

    insert(:resource_unavailability,
      start: DateTime.add(DateTime.utc_now(), -6 * 60, :minute),
      end: nil,
      resource_id: resource_2.id
    )

    insert(:resource_unavailability,
      start: DateTime.add(DateTime.utc_now(), -6 * 60 - 15, :minute),
      end: nil,
      resource_id: resource_gtfs.id
    )

    already_sent_email = "alreadysent@example.fr"
    insert_notification(%{dataset: dataset, role: :producer, reason: :resource_unavailable, email: already_sent_email})
    # Should be ignored because this is for another reason
    insert_notification(%{dataset: dataset, role: :producer, reason: :expiration, email: "foo@example.com"})
    # Should be ignored because it's for another dataset
    insert_notification(%{
      dataset: gtfs_dataset,
      role: :producer,
      reason: :resource_unavailable,
      email: "foo@example.com"
    })

    # Should be ignored because it's too old
    %{
      dataset: dataset,
      role: :producer,
      reason: :resource_unavailable,
      email: "foo@example.com",
      inserted_at: add_hours(-25)
    }
    |> insert_notification()

    setup_dataset_response(dataset, resource_1.url, DateTime.utc_now() |> DateTime.add(-6, :hour))

    %DB.Contact{id: already_sent_contact_id} = insert_contact(%{email: already_sent_email})
    %DB.Contact{id: foo_contact_id} = foo_contact = insert_contact(%{email: "foo@example.com"})
    %DB.Contact{id: reuser_contact_id} = reuser_contact = insert_contact(%{email: reuser_email = "reuser@example.com"})

    insert(:notification_subscription, %{
      reason: :resource_unavailable,
      source: :admin,
      role: :producer,
      contact_id: already_sent_contact_id,
      dataset_id: dataset.id
    })

    %DB.NotificationSubscription{id: ns_1} =
      insert(:notification_subscription, %{
        reason: :resource_unavailable,
        source: :admin,
        role: :producer,
        contact_id: foo_contact_id,
        dataset_id: dataset.id
      })

    %DB.NotificationSubscription{id: ns_2} =
      insert(:notification_subscription, %{
        reason: :resource_unavailable,
        source: :user,
        role: :reuser,
        contact_id: reuser_contact_id,
        dataset_id: dataset.id
      })

    %DB.Contact{id: bar_contact_id} = bar_contact = insert_contact(%{email: "bar@example.com"})

    %DB.NotificationSubscription{id: ns_3} =
      insert(:notification_subscription, %{
        reason: :resource_unavailable,
        source: :admin,
        role: :producer,
        contact_id: bar_contact_id,
        dataset_id: gtfs_dataset.id
      })

    assert :ok == perform_job(ResourceUnavailableNotificationJob, %{})

    # Emails have been sent
    display_name = DB.Contact.display_name(foo_contact)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, "foo@example.com"}],
                           subject: subject,
                           html_body: html_part
                         } ->
      assert subject == "Ressources indisponibles dans le jeu de données #{dataset.custom_title}"

      assert html_part =~
               ~s(Les ressources #{resource_1.title}, #{resource_2.title} dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> ne sont plus disponibles au téléchargement depuis plus de 6h.)

      assert html_part =~ "Il semble que vous ayez supprimé puis créé une nouvelle ressource"

      assert html_part =~
               ~s(rendez-vous sur votre <a href="http://127.0.0.1:5100/espace_producteur?utm_source=transactional_email&amp;utm_medium=email&amp;utm_campaign=resource_unavailable_producer">Espace Producteur</a> à partir duquel vous pourrez procéder à ces mises à jour)
    end)

    display_name = DB.Contact.display_name(reuser_contact)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, ^reuser_email}],
                           subject: subject,
                           html_body: html_part
                         } ->
      assert subject == "Ressources indisponibles dans le jeu de données #{dataset.custom_title}"

      assert html_part =~
               ~s(Les ressources #{resource_1.title}, #{resource_2.title} du jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> que vous réutilisez ne sont plus disponibles au téléchargement depuis plus de 6h.)

      assert html_part =~ "Nous avons déjà informé le producteur de ces données."
    end)

    display_name = DB.Contact.display_name(bar_contact)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{^display_name, "bar@example.com"}],
                           subject: subject,
                           html_body: html_part
                         } ->
      assert subject == "Ressources indisponibles dans le jeu de données #{gtfs_dataset.custom_title}"

      assert html_part =~
               ~s(Les ressources #{resource_gtfs.title} dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{gtfs_dataset.slug}">#{gtfs_dataset.custom_title}</a> ne sont plus disponibles au téléchargement depuis plus de 6h.)

      refute html_part =~ "Il semble que vous ayez supprimé puis créé une nouvelle ressource"

      assert html_part =~
               "Nous vous invitons à corriger l’accès à vos données dès que possible afin de ne pas perturber leur réutilisation."
    end)

    assert_no_email_sent()

    # Logs have been saved
    recent_dt = DateTime.utc_now() |> DateTime.add(-1, :second)

    assert DB.Notification |> DB.Repo.aggregate(:count) == 7

    assert %DB.Notification{
             notification_subscription_id: ^ns_1,
             role: :producer,
             payload: %{
               "deleted_recreated_on_datagouv" => true,
               "hours_consecutive_downtime" => 6,
               "resource_ids" => [^resource_1_id, ^resource_2_id],
               "job_id" => job_id_1
             }
           } =
             DB.Notification.base_query()
             |> where(
               [notification: n],
               n.email_hash == ^"foo@example.com" and n.inserted_at >= ^recent_dt and n.reason == :resource_unavailable and
                 n.dataset_id == ^dataset_id
             )
             |> DB.Repo.one!()

    assert %DB.Notification{
             notification_subscription_id: ^ns_2,
             dataset_id: ^dataset_id,
             reason: :resource_unavailable,
             role: :reuser,
             payload: %{
               "hours_consecutive_downtime" => 6,
               "producer_warned" => true,
               "resource_ids" => [^resource_1_id, ^resource_2_id],
               "job_id" => job_id_2
             }
           } =
             DB.Notification.base_query()
             |> where([notification: n], n.email_hash == ^reuser_email and n.inserted_at >= ^recent_dt)
             |> DB.Repo.one!()

    assert %DB.Notification{
             notification_subscription_id: ^ns_3,
             dataset_id: ^gtfs_dataset_id,
             role: :producer,
             reason: :resource_unavailable,
             payload: %{
               "deleted_recreated_on_datagouv" => false,
               "hours_consecutive_downtime" => 6,
               "resource_ids" => [^resource_gtfs_id],
               "job_id" => job_id_3
             }
           } =
             DB.Notification.base_query()
             |> where([notification: n], n.email_hash == ^"bar@example.com" and n.inserted_at >= ^recent_dt)
             |> DB.Repo.one!()

    assert MapSet.new([job_id_1, job_id_2, job_id_3]) |> Enum.count() == 1

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.ResourceUnavailableNotificationJob",
               args: %{
                 "dataset_id" => ^gtfs_dataset_id,
                 "resource_ids" => [^resource_gtfs_id],
                 "hours_consecutive_downtime" => 30
               },
               state: "scheduled",
               scheduled_at: scheduled_at_1
             },
             %Oban.Job{
               worker: "Transport.Jobs.ResourceUnavailableNotificationJob",
               args: %{
                 "dataset_id" => ^dataset_id,
                 "resource_ids" => [^resource_1_id, ^resource_2_id],
                 "hours_consecutive_downtime" => 30
               },
               state: "scheduled",
               scheduled_at: scheduled_at_2
             }
           ] = all_enqueued()

    assert_in_delta DateTime.to_unix(scheduled_at_1),
                    DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_unix(),
                    2

    assert_in_delta DateTime.to_unix(scheduled_at_2),
                    DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_unix(),
                    2
  end

  describe "perform when sending again" do
    test "when resources remain unavailable" do
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
      %DB.Resource{id: resource_1_id} = resource_1 = insert(:resource, dataset: dataset, is_available: false)

      %DB.Contact{id: foo_contact_id} = foo_contact = insert_contact()
      %DB.Contact{id: bar_contact_id} = bar_contact = insert_contact()

      %{id: ns_1} =
        insert(:notification_subscription, %{
          reason: :resource_unavailable,
          source: :admin,
          role: :producer,
          contact_id: foo_contact_id,
          dataset_id: dataset.id
        })

      %{id: ns_2} =
        insert(:notification_subscription, %{
          reason: :resource_unavailable,
          source: :admin,
          role: :reuser,
          contact_id: bar_contact_id,
          dataset_id: dataset.id
        })

      assert :ok ==
               perform_job(ResourceUnavailableNotificationJob, %{
                 dataset_id: dataset.id,
                 resource_ids: [resource_1.id],
                 hours_consecutive_downtime: 30
               })

      # Emails have been sent
      display_name = DB.Contact.display_name(foo_contact)
      foo_email = foo_contact.email

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{^display_name, ^foo_email}],
                             subject: subject,
                             html_body: html_part
                           } ->
        assert subject == "Ressources indisponibles dans le jeu de données #{dataset.custom_title}"

        assert html_part =~
                 ~s(Les ressources #{resource_1.title} dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> ne sont plus disponibles au téléchargement depuis plus de 30h.)
      end)

      display_name = DB.Contact.display_name(bar_contact)
      reuser_email = bar_contact.email

      assert_email_sent(fn %Swoosh.Email{
                             from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                             to: [{^display_name, ^reuser_email}],
                             subject: subject,
                             html_body: html_part
                           } ->
        assert subject == "Ressources indisponibles dans le jeu de données #{dataset.custom_title}"

        assert html_part =~
                 ~s(Les ressources #{resource_1.title} du jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> que vous réutilisez ne sont plus disponibles au téléchargement depuis plus de 30h.)

        assert html_part =~ "Nous avons déjà informé le producteur de ces données."
      end)

      # Logs have been saved
      recent_dt = DateTime.utc_now() |> DateTime.add(-1, :second)

      assert DB.Notification |> DB.Repo.aggregate(:count) == 2

      assert %DB.Notification{
               notification_subscription_id: ^ns_1,
               reason: :resource_unavailable,
               role: :producer,
               contact_id: ^foo_contact_id,
               payload: %{
                 "hours_consecutive_downtime" => 30,
                 "resource_ids" => [^resource_1_id],
                 "job_id" => job_id_1
               }
             } =
               DB.Notification.base_query()
               |> where(
                 [notification: n],
                 n.role == :producer and n.inserted_at >= ^recent_dt and n.dataset_id == ^dataset_id
               )
               |> DB.Repo.one!()

      assert %DB.Notification{
               notification_subscription_id: ^ns_2,
               reason: :resource_unavailable,
               role: :reuser,
               contact_id: ^bar_contact_id,
               payload: %{
                 "hours_consecutive_downtime" => 30,
                 "resource_ids" => [^resource_1_id],
                 "producer_warned" => true,
                 "job_id" => job_id_2
               }
             } =
               DB.Notification.base_query()
               |> where(
                 [notification: n],
                 n.role == :reuser and n.inserted_at >= ^recent_dt and n.dataset_id == ^dataset_id
               )
               |> DB.Repo.one!()

      assert job_id_1 == job_id_2

      # Next job has been enqueued
      assert [
               %Oban.Job{
                 worker: "Transport.Jobs.ResourceUnavailableNotificationJob",
                 args: %{
                   "dataset_id" => ^dataset_id,
                   "resource_ids" => [^resource_1_id],
                   "hours_consecutive_downtime" => 54
                 },
                 state: "scheduled",
                 scheduled_at: scheduled_at
               }
             ] = all_enqueued()

      assert_in_delta DateTime.to_unix(scheduled_at),
                      DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_unix(),
                      2
    end

    test "when resources are now available" do
      dataset = insert(:dataset)
      resource_1 = insert(:resource, dataset: dataset, is_available: true)

      foo_contact = insert_contact()
      bar_contact = insert_contact()

      insert(:notification_subscription, %{
        reason: :resource_unavailable,
        source: :admin,
        role: :producer,
        contact: foo_contact,
        dataset: dataset
      })

      insert(:notification_subscription, %{
        reason: :resource_unavailable,
        source: :admin,
        role: :reuser,
        contact: bar_contact,
        dataset: dataset
      })

      assert :ok ==
               perform_job(ResourceUnavailableNotificationJob, %{
                 dataset_id: dataset.id,
                 resource_ids: [resource_1.id],
                 hours_consecutive_downtime: 30
               })

      assert_no_email_sent()

      assert DB.Repo.all(DB.Notification) |> Enum.empty?()
      assert all_enqueued() |> Enum.empty?()
    end
  end

  describe "created_resource_hosted_on_datagouv_recently?" do
    test "base case" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}
      file_url = "https://static.data.gouv.fr/file.zip"
      assert DB.Resource.hosted_on_datagouv?(file_url)
      setup_dataset_response(dataset, file_url, DateTime.utc_now() |> DateTime.add(-6, :hour))
      assert ResourceUnavailableNotificationJob.created_resource_hosted_on_datagouv_recently?(dataset)
    end

    test "resource on datagouv has been created a long time ago" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}
      file_url = "https://static.data.gouv.fr/file.zip"
      assert DB.Resource.hosted_on_datagouv?(file_url)
      setup_dataset_response(dataset, file_url, DateTime.utc_now() |> DateTime.add(-24, :hour))
      refute ResourceUnavailableNotificationJob.created_resource_hosted_on_datagouv_recently?(dataset)
    end

    test "recent resource is not hosted on datagouv" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}
      file_url = "https://example.com/file.zip"
      refute DB.Resource.hosted_on_datagouv?(file_url)
      setup_dataset_response(dataset, file_url, DateTime.utc_now() |> DateTime.add(-6, :hour))
      refute ResourceUnavailableNotificationJob.created_resource_hosted_on_datagouv_recently?(dataset)
    end
  end

  test "email_addresses_already_sent" do
    dataset = insert(:dataset)

    %{
      dataset: dataset,
      role: :producer,
      reason: :resource_unavailable,
      email: "foo@example.com",
      inserted_at: add_hours(-20)
    }
    |> insert_notification()

    # Too old
    %{
      dataset: dataset,
      role: :producer,
      reason: :resource_unavailable,
      email: "bar@example.com",
      inserted_at: add_hours(-25)
    }
    |> insert_notification()

    # Another reason
    %{dataset: dataset, role: :producer, reason: :expiration, email: "baz@example.com", inserted_at: add_hours(-6)}
    |> insert_notification()

    assert ["foo@example.com"] == ResourceUnavailableNotificationJob.email_addresses_already_sent(dataset)
  end

  defp add_hours(days), do: DateTime.utc_now() |> DateTime.add(days, :hour)

  defp setup_dataset_response(%DB.Dataset{datagouv_id: datagouv_id}, resource_url, created_at) do
    url = "https://demo.data.gouv.fr/api/1/datasets/#{datagouv_id}/"

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: Jason.encode!(%{"resources" => [%{"url" => resource_url, "created_at" => created_at}]})
       }}
    end)
  end
end
