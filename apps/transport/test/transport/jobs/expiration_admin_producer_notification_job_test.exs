defmodule Transport.Test.Transport.Jobs.ExpirationAdminProducerNotificationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Swoosh.TestAssertions
  use Oban.Testing, repo: DB.Repo

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    on_exit(fn -> assert_no_email_sent() end)
  end

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

    assert :ok == perform_job(Transport.Jobs.ExpirationAdminProducerNotificationJob, %{})

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
    assert :ok == perform_job(Transport.Jobs.ExpirationAdminProducerNotificationJob, %{})
    assert_no_email_sent()
  end

  test "datasets_with_resources_expiring_on" do
    {today, tomorrow, yesterday} = {Date.utc_today(), Date.add(Date.utc_today(), 1), Date.add(Date.utc_today(), -1)}
    assert [] == today |> Transport.Expiration.datasets_with_resources_expiring_on()

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

    assert [] == today |> Transport.Expiration.datasets_with_resources_expiring_on()

    # 2 GTFS resources expiring on the same day for a dataset
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset, is_active: true)
    insert_fn.(today, dataset)
    insert_fn.(today, dataset)

    assert [
             {%DB.Dataset{id: ^dataset_id},
              [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
           ] = today |> Transport.Expiration.datasets_with_resources_expiring_on()

    assert [] == tomorrow |> Transport.Expiration.datasets_with_resources_expiring_on()
    assert [] == yesterday |> Transport.Expiration.datasets_with_resources_expiring_on()

    insert_fn.(tomorrow, dataset)

    assert [
             {%DB.Dataset{id: ^dataset_id},
              [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
           ] = today |> Transport.Expiration.datasets_with_resources_expiring_on()

    assert [
             {%DB.Dataset{id: ^dataset_id}, [%DB.Resource{dataset_id: ^dataset_id}]}
           ] = tomorrow |> Transport.Expiration.datasets_with_resources_expiring_on()

    assert [] == yesterday |> Transport.Expiration.datasets_with_resources_expiring_on()

    # Multiple datasets
    %DB.Dataset{id: d2_id} = d2 = insert(:dataset, is_active: true)
    insert_fn.(today, d2)

    assert [
             {%DB.Dataset{id: ^dataset_id},
              [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]},
             {%DB.Dataset{id: ^d2_id}, [%DB.Resource{dataset_id: ^d2_id}]}
           ] = today |> Transport.Expiration.datasets_with_resources_expiring_on()
  end

  test "datasets_with_resources_expiring_on works with both GTFS validators" do
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

    assert [{%DB.Dataset{id: ^d1_id}, _}] =
             Transport.Expiration.datasets_with_resources_expiring_on(today)

    assert [{%DB.Dataset{id: ^d2_id}, _}] =
             Transport.Expiration.datasets_with_resources_expiring_on(a_week_ago)
  end
end
