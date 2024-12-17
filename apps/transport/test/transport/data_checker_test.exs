defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory
  import Swoosh.TestAssertions
  use Oban.Testing, repo: DB.Repo

  doctest Transport.DataChecker, import: true

  setup :verify_on_exit!

  setup do
    # Using the real implementation for the moment, then it falls back on `HTTPoison.Mock`
    Mox.stub_with(Datagouvfr.Client.Datasets.Mock, Datagouvfr.Client.Datasets.External)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "inactive_data job" do
    test "warns our team of datasets reappearing on data gouv and reactivates them locally" do
      # we create a dataset which is considered not active on our side
      dataset = insert(:dataset, is_active: false)

      # the dataset is found on datagouv
      setup_datagouv_response(dataset, 200, %{archived: nil})

      # running the job
      Transport.DataChecker.inactive_data()

      assert_email_sent(
        from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
        to: "contact@transport.data.gouv.fr",
        subject: "Jeux de données supprimés ou archivés",
        text_body: nil,
        html_body: ~r/Certains jeux de données disparus sont réapparus sur data.gouv.fr/
      )

      # should result into marking the dataset back as active
      assert %DB.Dataset{is_active: true} = DB.Repo.reload!(dataset)
    end

    test "warns our team of datasets disappearing on data gouv and mark them as such locally" do
      # Create a bunch of random datasets to avoid triggering the safety net
      # of desactivating more than 10% of active datasets
      Enum.each(1..25, fn _ ->
        dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
        setup_datagouv_response(dataset, 200, %{archived: nil})
      end)

      # Getting timeout errors, should be ignored
      dataset_http_error = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
      api_url = "https://demo.data.gouv.fr/api/1/datasets/#{dataset_http_error.datagouv_id}/"

      Transport.HTTPoison.Mock
      |> expect(:request, 3, fn :get, ^api_url, "", [], [follow_redirect: true] ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      # We create a dataset which is considered active on our side
      # but which is not found (=> inactive) on data gouv side
      dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
      setup_datagouv_response(dataset, 404, %{})

      # We create a dataset which is considered active on our side
      # but we get a 500 error on data gouv side => we should not deactivate it
      dataset_500 = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())

      setup_datagouv_response(dataset_500, 500, %{})

      # we create a dataset which is considered active on our side
      # but private on datagouv, resulting on a HTTP code 410
      dataset_410 = insert(:dataset, is_active: true)

      setup_datagouv_response(dataset_410, 410, %{})

      # This dataset does not have a producer anymore
      dataset_no_producer = insert(:dataset, is_active: true)

      setup_datagouv_response(dataset_no_producer, 200, %{owner: nil, organization: nil, archived: nil})

      # running the job
      Transport.DataChecker.inactive_data()

      assert_email_sent(
        from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
        to: "contact@transport.data.gouv.fr",
        subject: "Jeux de données supprimés ou archivés",
        text_body: nil,
        html_body: ~r/Certains jeux de données ont disparus de data.gouv.fr/
      )

      # should result into marking the dataset as inactive
      assert %DB.Dataset{is_active: false} = DB.Repo.reload!(dataset)
      # we got HTTP timeout errors: we should not deactivate the dataset
      assert %DB.Dataset{is_active: true} = DB.Repo.reload!(dataset_http_error)
      # we got a 500 error: we should not deactivate the dataset
      assert %DB.Dataset{is_active: true} = DB.Repo.reload!(dataset_500)
      # we got a 410 GONE HTTP code: we should deactivate the dataset
      assert %DB.Dataset{is_active: false} = DB.Repo.reload!(dataset_410)
      # no owner or organization: we should deactivate the dataset
      assert %DB.Dataset{is_active: false} = DB.Repo.reload!(dataset_no_producer)
    end

    test "sends an email when a dataset is now archived" do
      dataset = insert(:dataset, is_active: true)

      setup_datagouv_response(dataset, 200, %{archived: DateTime.utc_now() |> DateTime.add(-10, :hour)})

      Transport.DataChecker.inactive_data()

      assert_email_sent(
        from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
        to: "contact@transport.data.gouv.fr",
        subject: "Jeux de données supprimés ou archivés",
        text_body: nil,
        html_body: ~r/Certains jeux de données sont indiqués comme archivés/
      )
    end

    test "does not send email if nothing has disappeared or reappeared" do
      assert DB.Repo.aggregate(DB.Dataset, :count) == 0

      Transport.HTTPoison.Mock
      |> expect(:head, 0, fn _ -> nil end)

      Transport.DataChecker.inactive_data()

      assert_no_email_sent()
    end
  end

  test "gtfs_datasets_expiring_on" do
    {today, tomorrow, yesterday} = {Date.utc_today(), Date.add(Date.utc_today(), 1), Date.add(Date.utc_today(), -1)}
    assert [] == today |> Transport.DataChecker.gtfs_datasets_expiring_on()

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

    assert [] == today |> Transport.DataChecker.gtfs_datasets_expiring_on()

    # 2 GTFS resources expiring on the same day for a dataset
    %DB.Dataset{id: dataset_id} = dataset = insert(:dataset, is_active: true)
    insert_fn.(today, dataset)
    insert_fn.(today, dataset)

    assert [
             {%DB.Dataset{id: ^dataset_id},
              [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
           ] = today |> Transport.DataChecker.gtfs_datasets_expiring_on()

    assert [] == tomorrow |> Transport.DataChecker.gtfs_datasets_expiring_on()
    assert [] == yesterday |> Transport.DataChecker.gtfs_datasets_expiring_on()

    insert_fn.(tomorrow, dataset)

    assert [
             {%DB.Dataset{id: ^dataset_id},
              [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]}
           ] = today |> Transport.DataChecker.gtfs_datasets_expiring_on()

    assert [
             {%DB.Dataset{id: ^dataset_id}, [%DB.Resource{dataset_id: ^dataset_id}]}
           ] = tomorrow |> Transport.DataChecker.gtfs_datasets_expiring_on()

    assert [] == yesterday |> Transport.DataChecker.gtfs_datasets_expiring_on()

    # Multiple datasets
    %DB.Dataset{id: d2_id} = d2 = insert(:dataset, is_active: true)
    insert_fn.(today, d2)

    assert [
             {%DB.Dataset{id: ^dataset_id},
              [%DB.Resource{dataset_id: ^dataset_id}, %DB.Resource{dataset_id: ^dataset_id}]},
             {%DB.Dataset{id: ^d2_id}, [%DB.Resource{dataset_id: ^d2_id}]}
           ] = today |> Transport.DataChecker.gtfs_datasets_expiring_on()
  end

  describe "outdated_data job" do
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
               Date.utc_today() |> Transport.DataChecker.gtfs_datasets_expiring_on()

      %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

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

      assert :ok == perform_job(Transport.Jobs.OutdatedDataNotificationJob, %{})

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
    end

    test "outdated_data job with nothing to send should not send email" do
      assert :ok == perform_job(Transport.Jobs.OutdatedDataNotificationJob, %{})
      assert_no_email_sent()
    end
  end

  test "send_outdated_data_notifications" do
    %{id: dataset_id} = dataset = insert(:dataset)
    %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

    %DB.NotificationSubscription{id: ns_id} =
      insert(:notification_subscription, %{
        reason: :expiration,
        source: :admin,
        role: :producer,
        contact_id: contact_id,
        dataset_id: dataset.id
      })

    job_id = 42
    Transport.DataChecker.send_outdated_data_producer_notifications({7, [{dataset, []}]}, job_id)

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: {DB.Contact.display_name(contact), email},
      subject: "Jeu de données arrivant à expiration",
      text_body: nil,
      html_body: ~r/Bonjour/
    )

    assert [
             %DB.Notification{
               contact_id: ^contact_id,
               email: ^email,
               reason: :expiration,
               dataset_id: ^dataset_id,
               notification_subscription_id: ^ns_id,
               role: :producer,
               payload: %{"delay" => 7, "job_id" => ^job_id}
             }
           ] =
             DB.Notification |> DB.Repo.all()
  end

  describe "dataset_status" do
    test "active" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}

      setup_datagouv_response(dataset, 200, %{archived: nil})

      assert :active = Transport.DataChecker.dataset_status(dataset)
    end

    test "archived" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}

      setup_datagouv_response(dataset, 200, %{archived: datetime = DateTime.utc_now()})

      assert {:archived, datetime} == Transport.DataChecker.dataset_status(dataset)
    end

    test "inactive" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}

      Enum.each([404, 410], fn status ->
        setup_datagouv_response(dataset, status, %{})

        assert :inactive = Transport.DataChecker.dataset_status(dataset)
      end)
    end

    test "no_producer" do
      dataset = %DB.Dataset{datagouv_id: Ecto.UUID.generate()}

      setup_datagouv_response(dataset, 200, %{owner: nil, organization: nil, archived: nil})

      assert :no_producer = Transport.DataChecker.dataset_status(dataset)
    end

    test "ignore" do
      dataset = %DB.Dataset{datagouv_id: datagouv_id = Ecto.UUID.generate()}
      url = "https://demo.data.gouv.fr/api/1/datasets/#{datagouv_id}/"

      Transport.HTTPoison.Mock
      |> expect(:request, 3, fn :get, ^url, "", [], [follow_redirect: true] ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      assert :ignore = Transport.DataChecker.dataset_status(dataset)
    end
  end

  defp setup_datagouv_response(%DB.Dataset{datagouv_id: datagouv_id}, status, body) do
    url = "https://demo.data.gouv.fr/api/1/datasets/#{datagouv_id}/"

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: status, body: Jason.encode!(body)}}
    end)
  end
end
