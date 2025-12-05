defmodule Transport.Test.Transport.Jobs.MultiValidationWithErrorNotificationJobTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Swoosh.TestAssertions
  alias Transport.Jobs.MultiValidationWithErrorNotificationJob

  doctest MultiValidationWithErrorNotificationJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "relevant_validations" do
    test "base case" do
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
      geojson_resource = insert(:resource, dataset: dataset, format: "geojson")

      rh_geojson_resource = insert(:resource_history, resource: geojson_resource)

      insert(:multi_validation, %{
        validator: Transport.Validators.GTFSRT.validator_name(),
        resource: insert(:resource, dataset: dataset, format: "gtfs-rt"),
        max_error: "ERROR"
      })

      %DB.MultiValidation{id: mv_id} =
        insert(:multi_validation, %{
          resource_history: rh_geojson_resource,
          validator: Transport.Validators.EXJSONSchema.validator_name(),
          result: %{"has_errors" => true},
          inserted_at: DateTime.utc_now() |> DateTime.add(-45, :minute)
        })

      # Should be empty because:
      # - real-time validations (for GTFS-RT) are ignored
      # - the GeoJSON is too old (45 minutes)
      assert %{} == MultiValidationWithErrorNotificationJob.relevant_validations(DateTime.utc_now())

      # Finds the GeoJSON validation because it was created 45 minutes ago
      dt_limit = DateTime.utc_now() |> DateTime.add(-30, :minute)
      relevant_validations = MultiValidationWithErrorNotificationJob.relevant_validations(dt_limit)
      assert [%DB.Dataset{id: ^dataset_id}] = relevant_validations |> Map.keys()
      assert [[%DB.MultiValidation{id: ^mv_id}]] = relevant_validations |> Map.values()
    end

    test "finds multi validation for real-time data" do
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
      gbfs = insert(:resource, format: "gbfs", dataset: dataset)

      %DB.MultiValidation{id: mv_id} =
        insert(:multi_validation, %{
          resource_id: gbfs.id,
          validator: Transport.Validators.GBFSValidator.validator_name(),
          result: %{"has_errors" => true},
          inserted_at: DateTime.utc_now() |> DateTime.add(-15, :minute)
        })

      dt_limit = DateTime.utc_now() |> DateTime.add(-30, :minute)
      relevant_validations = MultiValidationWithErrorNotificationJob.relevant_validations(dt_limit)
      assert [%DB.Dataset{id: ^dataset_id}] = relevant_validations |> Map.keys()
      assert [[%DB.MultiValidation{id: ^mv_id}]] = relevant_validations |> Map.values()
    end

    test "finds the MobilityData validator" do
      %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
      gtfs = insert(:resource, format: "GTFS", dataset: dataset)

      %DB.MultiValidation{id: mv_id} =
        insert(:multi_validation, %{
          resource_history: insert(:resource_history, resource: gtfs),
          validator: Transport.Validators.MobilityDataGTFSValidator.validator_name(),
          max_error: "ERROR",
          inserted_at: DateTime.utc_now() |> DateTime.add(-15, :minute)
        })

      dt_limit = DateTime.utc_now() |> DateTime.add(-30, :minute)
      relevant_validations = MultiValidationWithErrorNotificationJob.relevant_validations(dt_limit)
      assert [%DB.Dataset{id: ^dataset_id}] = relevant_validations |> Map.keys()
      assert [[%DB.MultiValidation{id: ^mv_id}]] = relevant_validations |> Map.values()
    end
  end

  test "perform for multiple static data cases" do
    # 2 datasets in scope, with different validators
    # 1 GTFS dataset with a resource, another dataset with a JSON schema and 2 errors
    %{id: dataset_id} = dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")

    %{id: gtfs_dataset_id} =
      gtfs_dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Dataset GTFS")

    %DB.Resource{id: resource_1_id} =
      resource_1 = insert(:resource, dataset: dataset, format: "geojson", title: "GeoJSON 1")

    %DB.Resource{id: resource_2_id} =
      resource_2 = insert(:resource, dataset: dataset, format: "geojson", title: "GeoJSON 2")

    %DB.Resource{id: resource_gtfs_id} = resource_gtfs = insert(:resource, dataset: gtfs_dataset, format: "GTFS")
    rh_resource_1 = insert(:resource_history, resource: resource_1)
    rh_resource_2 = insert(:resource_history, resource: resource_2)
    rh_resource_gtfs = insert(:resource_history, resource: resource_gtfs)

    insert(:multi_validation, %{
      resource_history: rh_resource_1,
      validator: jsonschema_validator_name = Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: rh_resource_2,
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: rh_resource_gtfs,
      validator: gtfs_validator_name = Transport.Validators.GTFSTransport.validator_name(),
      max_error: "Fatal"
    })

    already_sent_email = "alreadysent@example.fr"
    insert_notification(%{dataset: dataset, role: :producer, reason: :dataset_with_error, email: already_sent_email})
    # Should be ignored because this is for another reason
    insert_notification(%{dataset: dataset, role: :producer, reason: :expiration, email: "foo@example.com"})
    # Should be ignored because it's for another dataset
    insert_notification(%{
      dataset: gtfs_dataset,
      role: :producer,
      reason: :dataset_with_error,
      email: "foo@example.com"
    })

    # Should be ignored because it's too old
    %{dataset: dataset, role: :producer, reason: :dataset_with_error, email: "foo@example.com"}
    |> insert_notification()
    |> Ecto.Changeset.change(%{inserted_at: DateTime.utc_now() |> DateTime.add(-20, :day)})
    |> DB.Repo.update!()

    %DB.Contact{id: already_sent_contact_id} = insert_contact(%{email: already_sent_email})
    %DB.Contact{id: foo_contact_id} = foo_contact = insert_contact(%{email: "foo@example.com"})
    %DB.Contact{id: reuser_contact_id} = reuser_contact = insert_contact(%{email: reuser_email = "reuser@example.com"})

    # Subscriptions for a contact who was already warned, a producer and a reuser
    insert(:notification_subscription, %{
      reason: :dataset_with_error,
      source: :admin,
      role: :producer,
      contact_id: already_sent_contact_id,
      dataset_id: dataset.id
    })

    %DB.NotificationSubscription{id: subscription_foo_id} =
      insert(:notification_subscription, %{
        reason: :dataset_with_error,
        source: :admin,
        role: :producer,
        contact_id: foo_contact_id,
        dataset_id: dataset.id
      })

    %DB.NotificationSubscription{id: subscription_reuser_id} =
      insert(:notification_subscription, %{
        reason: :dataset_with_error,
        source: :user,
        role: :reuser,
        contact_id: reuser_contact_id,
        dataset_id: dataset.id
      })

    # Contact + subscription for another dataset
    %DB.Contact{id: bar_contact_id} = bar_contact = insert_contact(%{email: "bar@example.com"})

    %DB.NotificationSubscription{id: subscription_bar_id} =
      insert(:notification_subscription, %{
        reason: :dataset_with_error,
        source: :admin,
        role: :producer,
        contact_id: bar_contact_id,
        dataset_id: gtfs_dataset.id
      })

    assert :ok == perform_job(MultiValidationWithErrorNotificationJob, %{})

    assert_email_sent(fn %Swoosh.Email{to: to, subject: subject, html_body: html} ->
      assert to == [{DB.Contact.display_name(foo_contact), foo_contact.email}]
      assert subject == "Erreurs détectées dans le jeu de données #{dataset.custom_title}"

      assert html =~
               ~s(Des erreurs bloquantes ont été détectées dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~
               ~s(<a href="http://127.0.0.1:5100/resources/#{resource_1.id}">#{resource_1.title}</a>)

      assert html =~
               ~s(<a href="http://127.0.0.1:5100/resources/#{resource_2.id}">#{resource_2.title}</a>)
    end)

    assert_email_sent(fn %Swoosh.Email{to: to, subject: subject, html_body: html} ->
      assert to == [{DB.Contact.display_name(reuser_contact), reuser_email}]
      assert subject == "Erreurs détectées dans le jeu de données #{dataset.custom_title}"

      assert html =~
               ~s(Des erreurs bloquantes ont été détectées dans le jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> que vous réutilisez.)

      assert html =~ "Nous avons déjà informé le producteur de ces données."
    end)

    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: to,
                           subject: subject,
                           html_body: html
                         } ->
      assert to == [{DB.Contact.display_name(bar_contact), bar_contact.email}]
      assert subject == "Erreurs détectées dans le jeu de données #{gtfs_dataset.custom_title}"

      assert html =~
               ~s(Des erreurs bloquantes ont été détectées dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{gtfs_dataset.slug}">#{gtfs_dataset.custom_title}</a>)

      assert html =~
               ~s(<a href="http://127.0.0.1:5100/resources/#{resource_gtfs.id}">#{resource_gtfs.title}</a>)
    end)

    # Checks no other emails have been sent
    assert_no_email_sent()

    # Logs have been saved
    recent_dt = DateTime.utc_now() |> DateTime.add(-1, :second)

    assert %DB.Notification{
             role: :producer,
             payload: %{
               "resource_formats" => ["geojson", "geojson"],
               "resource_ids" => [^resource_1_id, ^resource_2_id],
               "validator_name" => ^jsonschema_validator_name,
               "job_id" => job_id
             },
             notification_subscription_id: ^subscription_foo_id
           } =
             DB.Notification.base_query()
             |> where(
               [notification: n],
               n.email_hash == ^"foo@example.com" and n.dataset_id == ^dataset_id and n.inserted_at >= ^recent_dt and
                 n.reason == :dataset_with_error
             )
             |> DB.Repo.one!()

    assert %DB.Notification{
             role: :reuser,
             reason: :dataset_with_error,
             payload: %{
               "producer_warned" => true,
               "validator_name" => ^jsonschema_validator_name,
               "job_id" => reuser_job_id
             },
             notification_subscription_id: ^subscription_reuser_id
           } =
             DB.Notification.base_query()
             |> where(
               [notification: n],
               n.email_hash == ^reuser_email and n.dataset_id == ^dataset_id and n.inserted_at >= ^recent_dt
             )
             |> DB.Repo.one!()

    assert %DB.Notification{
             role: :producer,
             reason: :dataset_with_error,
             payload: %{
               "resource_formats" => ["GTFS"],
               "resource_ids" => [^resource_gtfs_id],
               "validator_name" => ^gtfs_validator_name,
               "job_id" => bar_job_id
             },
             notification_subscription_id: ^subscription_bar_id
           } =
             DB.Notification.base_query()
             |> where(
               [notification: n],
               n.email_hash == ^"bar@example.com" and n.dataset_id == ^gtfs_dataset_id and n.inserted_at >= ^recent_dt
             )
             |> DB.Repo.one!()

    assert MapSet.new([job_id, reuser_job_id, bar_job_id]) |> Enum.count() == 1
  end

  test "perform for a real-time error dataset" do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    %DB.Resource{id: gbfs_id} = gbfs = insert(:resource, dataset: dataset, format: "gbfs")

    insert(:multi_validation, %{
      resource: gbfs,
      validator: gbfs_validator_name = Transport.Validators.GBFSValidator.validator_name(),
      result: %{"has_errors" => true}
    })

    %DB.Contact{id: producer_contact_id} = producer_contact = insert_contact()

    %DB.NotificationSubscription{id: subscription_producer_id} =
      insert(:notification_subscription, %{
        reason: :dataset_with_error,
        source: :admin,
        role: :producer,
        contact_id: producer_contact_id,
        dataset_id: dataset.id
      })

    # An error notification was already sent to another producer in the last 30 days.
    # The other producer should not be warned again.
    %DB.Contact{email: already_sent_email} = insert_contact()

    %DB.Notification{id: previous_notification_id} =
      %{dataset: dataset, role: :producer, reason: :dataset_with_error, email: already_sent_email}
      |> insert_notification()
      |> Ecto.Changeset.change(%{inserted_at: DateTime.utc_now() |> DateTime.add(-25, :day)})
      |> DB.Repo.update!()

    assert :ok == perform_job(MultiValidationWithErrorNotificationJob, %{})

    assert_email_sent(fn %Swoosh.Email{to: to, subject: subject, html_body: html} ->
      assert to == [{DB.Contact.display_name(producer_contact), producer_contact.email}]
      assert subject == "Erreurs détectées dans le jeu de données #{dataset.custom_title}"

      assert html =~
               ~s(Des erreurs bloquantes ont été détectées dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~
               ~s(<a href="http://127.0.0.1:5100/resources/#{gbfs.id}">#{gbfs.title}</a>)
    end)

    # Checks no other emails have been sent
    assert_no_email_sent()

    # Logs have been saved
    assert [
             %DB.Notification{id: ^previous_notification_id},
             %DB.Notification{
               contact_id: ^producer_contact_id,
               dataset_id: ^dataset_id,
               role: :producer,
               payload: %{
                 "resource_formats" => ["gbfs"],
                 "resource_ids" => [^gbfs_id],
                 "validator_name" => ^gbfs_validator_name,
                 "job_id" => _
               },
               notification_subscription_id: ^subscription_producer_id
             }
           ] = DB.Notification |> DB.Repo.all() |> Enum.sort_by(& &1.inserted_at, DateTime)
  end

  test "perform when a real-time notification was already sent and we have an error for static data" do
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset)
    %DB.Resource{} = gbfs = insert(:resource, dataset: dataset, format: "gbfs")
    %DB.Resource{id: geojson_id} = geojson = insert(:resource, dataset: dataset, format: "geojson")

    # Both resources have an error **now**
    insert(:multi_validation, %{
      resource: gbfs,
      validator: gbfs_validator_name = Transport.Validators.GBFSValidator.validator_name(),
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: insert(:resource_history, resource: geojson),
      validator: geojson_validator_name = Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"has_errors" => true}
    })

    %DB.Contact{id: producer_contact_id} = producer_contact = insert_contact()

    %DB.NotificationSubscription{id: subscription_producer_id} =
      insert(:notification_subscription, %{
        reason: :dataset_with_error,
        source: :admin,
        role: :producer,
        contact_id: producer_contact_id,
        dataset_id: dataset.id
      })

    # We already sent an error notification regarding the real time resource (GBFS) in the last 30 days
    {gbfs_sending_delay, :day} = MultiValidationWithErrorNotificationJob.sending_delay_by_validator(gbfs_validator_name)

    %DB.Notification{id: previous_notification_id} =
      %{
        dataset: dataset,
        role: :producer,
        reason: :dataset_with_error,
        email: producer_contact.email,
        payload: %{validator_name: gbfs_validator_name}
      }
      |> insert_notification()
      |> Ecto.Changeset.change(%{inserted_at: DateTime.utc_now() |> DateTime.add(-(gbfs_sending_delay - 5), :day)})
      |> DB.Repo.update!()

    assert :ok == perform_job(MultiValidationWithErrorNotificationJob, %{})

    # We send a single email related to the static resource (geojson)
    assert_email_sent(fn %Swoosh.Email{to: to, subject: subject, html_body: html} ->
      assert to == [{DB.Contact.display_name(producer_contact), producer_contact.email}]
      assert subject == "Erreurs détectées dans le jeu de données #{dataset.custom_title}"

      assert html =~
               ~s(Des erreurs bloquantes ont été détectées dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a>)

      assert html =~
               ~s(<a href="http://127.0.0.1:5100/resources/#{geojson.id}">#{geojson.title}</a>)
    end)

    # Checks no other emails have been sent
    assert_no_email_sent()

    # Logs have been saved
    assert [
             %DB.Notification{id: ^previous_notification_id},
             %DB.Notification{
               contact_id: ^producer_contact_id,
               dataset_id: ^dataset_id,
               role: :producer,
               payload: %{
                 "resource_formats" => ["geojson"],
                 "resource_ids" => [^geojson_id],
                 "validator_name" => ^geojson_validator_name,
                 "job_id" => _
               },
               notification_subscription_id: ^subscription_producer_id
             }
           ] = DB.Notification |> DB.Repo.all() |> Enum.sort_by(& &1.inserted_at, DateTime)
  end

  test "email_addresses_already_sent" do
    dataset = insert(:dataset)
    validator_name = Transport.Validators.GTFSTransport.validator_name()

    %{
      dataset: dataset,
      role: :producer,
      reason: :dataset_with_error,
      email: "foo@example.com",
      inserted_at: add_days(-6)
    }
    |> insert_notification()

    # For a reuser
    %{
      dataset: dataset,
      role: :reuser,
      reason: :dataset_with_error,
      email: "baz@example.com",
      inserted_at: add_days(-6)
    }
    |> insert_notification()

    # Too old
    %{
      dataset: dataset,
      role: :producer,
      reason: :dataset_with_error,
      email: "bar@example.com",
      inserted_at: add_days(-8)
    }
    |> insert_notification()

    # Another reason
    %{dataset: dataset, role: :producer, reason: :expiration, email: "baz@example.com", inserted_at: add_days(-6)}
    |> insert_notification()

    assert MapSet.new(["baz@example.com", "foo@example.com"]) ==
             MultiValidationWithErrorNotificationJob.email_addresses_already_sent(dataset, validator_name)
             |> MapSet.new()
  end

  defp add_days(days), do: DateTime.utc_now() |> DateTime.add(days, :day)
end
