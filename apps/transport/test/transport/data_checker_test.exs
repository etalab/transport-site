defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory

  doctest Transport.DataChecker, import: true

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "inactive_data job" do
    test "warns our team of datasets reappearing on data gouv and reactivates them locally" do
      # we create a dataset which is considered not active on our side
      dataset = insert(:dataset, is_active: false)

      # but which is found (= active?) on data gouv side
      url = "https://demo.data.gouv.fr/api/1/datasets/#{dataset.datagouv_id}/"

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
        # the dataset is found on datagouv
        {:ok, %HTTPoison.Response{status_code: 200, body: ~s({"archived":null})}}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données supprimés ou archivés"
        assert body =~ ~r/Certains jeux de données disparus sont réapparus sur data.gouv.fr/
        :ok
      end)

      # running the job (...)
      Transport.DataChecker.inactive_data()

      # should result into marking the dataset back as active
      assert %DB.Dataset{is_active: true} = DB.Repo.reload!(dataset)

      verify!(Transport.HTTPoison.Mock)
      verify!(Transport.EmailSender.Mock)
    end

    test "warns our team of datasets disappearing on data gouv and mark them as such locally" do
      # Create a bunch of random datasets to avoid triggering the safety net
      # of desactivating more than 10% of active datasets
      Enum.each(1..10, fn _ ->
        dataset = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
        api_url = "https://demo.data.gouv.fr/api/1/datasets/#{dataset.datagouv_id}/"

        Transport.HTTPoison.Mock
        |> expect(:request, fn :get, ^api_url, "", [], [follow_redirect: true] ->
          {:ok, %HTTPoison.Response{status_code: 200, body: ~s({"archived":null})}}
        end)
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
      api_url = "https://demo.data.gouv.fr/api/1/datasets/#{dataset.datagouv_id}/"

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, ^api_url, "", [], [follow_redirect: true] ->
        # the dataset is not found on datagouv
        {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
      end)

      # We create a dataset which is considered active on our side
      # but we get a 500 error on data gouv side => we should not deactivate it
      dataset_500 = insert(:dataset, is_active: true, datagouv_id: Ecto.UUID.generate())
      api_url_500 = "https://demo.data.gouv.fr/api/1/datasets/#{dataset_500.datagouv_id}/"

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, ^api_url_500, "", [], [follow_redirect: true] ->
        # data.gouv answers with a 500
        {:ok, %HTTPoison.Response{status_code: 500, body: ""}}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données supprimés ou archivés"
        assert body =~ ~r/Certains jeux de données ont disparus de data.gouv.fr/
        :ok
      end)

      # running the job (...)
      Transport.DataChecker.inactive_data()

      # should result into marking the dataset as inactive
      assert %DB.Dataset{is_active: false} = DB.Repo.reload!(dataset)
      # we got HTTP timeout errors: we should not deactivate the dataset
      assert %DB.Dataset{is_active: true} = DB.Repo.reload!(dataset_http_error)
      # we got a 500 error: we should not deactivate the dataset
      assert %DB.Dataset{is_active: true} = DB.Repo.reload!(dataset_500)

      verify!(Transport.HTTPoison.Mock)
      verify!(Transport.EmailSender.Mock)
    end

    test "sends an email when a dataset is now archived" do
      dataset = insert(:dataset, is_active: true)

      # dataset is now archived on data.gouv.fr
      url = "https://demo.data.gouv.fr/api/1/datasets/#{dataset.datagouv_id}/"

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
        archived = DateTime.utc_now() |> DateTime.add(-10, :hour) |> DateTime.to_string()
        # the dataset is not found on datagouv
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"archived" => archived})}}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données supprimés ou archivés"
        assert body =~ ~r/Certains jeux de données sont indiqués comme archivés/
        :ok
      end)

      Transport.DataChecker.inactive_data()

      verify!(Transport.HTTPoison.Mock)
      verify!(Transport.EmailSender.Mock)
    end

    test "does not send email if nothing has disappeared or reappeared" do
      assert DB.Repo.aggregate(DB.Dataset, :count) == 0

      Transport.HTTPoison.Mock
      |> expect(:head, 0, fn _ -> nil end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> nil end)

      Transport.DataChecker.inactive_data()

      verify!(Transport.HTTPoison.Mock)
      verify!(Transport.EmailSender.Mock)
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

    # 2 resources expiring on the same day
    dataset = insert(:dataset, is_active: true)
    insert_fn.(today, dataset)
    insert_fn.(today, dataset)

    assert [dataset.id] == today |> Transport.DataChecker.gtfs_datasets_expiring_on() |> Enum.map(& &1.id)
    assert [] == tomorrow |> Transport.DataChecker.gtfs_datasets_expiring_on()
    assert [] == yesterday |> Transport.DataChecker.gtfs_datasets_expiring_on()

    insert_fn.(tomorrow, dataset)
    assert [dataset.id] == today |> Transport.DataChecker.gtfs_datasets_expiring_on() |> Enum.map(& &1.id)
    assert [dataset.id] == tomorrow |> Transport.DataChecker.gtfs_datasets_expiring_on() |> Enum.map(& &1.id)
    assert [] == yesterday |> Transport.DataChecker.gtfs_datasets_expiring_on()

    # Multiple datasets
    d2 = insert(:dataset, is_active: true)
    insert_fn.(today, d2)

    assert [dataset.id, d2.id] |> Enum.sort() ==
             today |> Transport.DataChecker.gtfs_datasets_expiring_on() |> Enum.map(& &1.id) |> Enum.sort()
  end

  describe "outdated_data job" do
    test "sends email to our team + relevant contact before expiry" do
      dataset = insert(:dataset, is_active: true, custom_title: "Dataset custom title")
      # fake a resource expiring today
      resource = insert(:resource, dataset: dataset, format: "GTFS")

      multi_validation =
        insert(:multi_validation,
          validator: Transport.Validators.GTFSTransport.validator_name(),
          resource_history: insert(:resource_history, resource_id: resource.id)
        )

      insert(:resource_metadata,
        multi_validation_id: multi_validation.id,
        metadata: %{"end_date" => Date.utc_today()}
      )

      assert [dataset.id] == Date.utc_today() |> Transport.DataChecker.gtfs_datasets_expiring_on() |> Enum.map(& &1.id)

      %DB.Contact{id: contact_id, email: producer_email} = insert_contact()

      insert(:notification_subscription, %{
        reason: :expiration,
        source: :admin,
        contact_id: contact_id,
        dataset_id: dataset.id
      })

      # a first mail to our team
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données arrivant à expiration"
        assert body =~ ~r/Jeux de données expirant demain :/

        assert body =~
                 "#{dataset.custom_title} - http://127.0.0.1:5100/datasets/#{dataset.slug} (✅ notification automatique)"

        :ok
      end)

      # a second mail to the email address in the notifications config
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == producer_email
        assert subject == "Jeu de données arrivant à expiration"
        assert body =~ ~r/Une ressource associée au jeu de données expire demain/
        refute body =~ "notification automatique"
        :ok
      end)

      Transport.DataChecker.outdated_data()

      verify!(Transport.EmailSender.Mock)
    end

    test "outdated_data job with nothing to send should not send email" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> nil end)

      Transport.DataChecker.outdated_data()

      verify!(Transport.EmailSender.Mock)
    end
  end

  test "send_outdated_data_notifications" do
    %{id: dataset_id} = dataset = insert(:dataset)
    %DB.Contact{id: contact_id, email: email} = insert_contact()

    insert(:notification_subscription, %{
      reason: :expiration,
      source: :admin,
      contact_id: contact_id,
      dataset_id: dataset.id
    })

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email = _to,
                             "contact@transport.beta.gouv.fr",
                             "Jeu de données arrivant à expiration" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ ~r/Bonjour/
      :ok
    end)

    Transport.DataChecker.send_outdated_data_notifications({7, [dataset]})

    assert [%DB.Notification{email: ^email, reason: :expiration, dataset_id: ^dataset_id}] =
             DB.Notification |> DB.Repo.all()

    verify!(Transport.EmailSender.Mock)
  end

  describe "send_new_dataset_notifications" do
    test "no datasets" do
      assert Transport.DataChecker.send_new_dataset_notifications([]) == :ok
    end

    test "with datasets" do
      %DB.Dataset{id: dataset_id, slug: slug} =
        dataset = insert(:dataset, custom_title: "Super JDD", type: "public-transit", slug: Ecto.UUID.generate())

      %DB.Contact{id: contact_id, email: email} = insert_contact()
      insert(:notification_subscription, %{reason: :new_dataset, source: :admin, contact_id: contact_id})

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr",
                               "contact@transport.beta.gouv.fr",
                               ^email = _to,
                               "contact@transport.beta.gouv.fr",
                               "Nouveaux jeux de données référencés" = _subject,
                               plain_text_body,
                               "" = _html_part ->
        assert plain_text_body =~ ~r/^Bonjour/

        assert plain_text_body =~
                 "* Super JDD - (Transport public collectif - horaires théoriques) - http://127.0.0.1:5100/datasets/#{slug}"

        :ok
      end)

      Transport.DataChecker.send_new_dataset_notifications([dataset])

      assert [%DB.Notification{email: ^email, reason: :new_dataset, dataset_id: ^dataset_id}] =
               DB.Notification |> DB.Repo.all()

      verify!(Transport.EmailSender.Mock)
    end
  end

  test "count_archived_datasets" do
    insert(:dataset, is_active: true, archived_at: nil)
    insert(:dataset, is_active: true, archived_at: DateTime.utc_now())
    insert(:dataset, is_active: false, archived_at: DateTime.utc_now())

    assert 1 == Transport.DataChecker.count_archived_datasets()
  end
end
