defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory

  setup :verify_on_exit!

  describe "inactive_data job" do
    test "warns our team of datasets reappearing on data gouv and reactivates them locally" do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

      # we create a dataset which is considered not active on our side
      dataset = insert(:dataset, is_active: false)

      # but which is found (= active?) on data gouv side
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/123/", "", [], [follow_redirect: true] ->
        # the dataset is found on datagouv
        {:ok, %HTTPoison.Response{status_code: 200, body: ~s({"archived":null})}}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données qui disparaissent"
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
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

      # we create a dataset which is considered active on our side
      dataset = insert(:dataset, is_active: true)

      # but which is not found found (= inactive?) on data gouv side
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/123/", "", [], [follow_redirect: true] ->
        # the dataset is not found on datagouv
        {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données qui disparaissent"
        assert body =~ ~r/Certains jeux de données ont disparus de data.gouv.fr/
        :ok
      end)

      # running the job (...)
      Transport.DataChecker.inactive_data()

      # should result into marking the dataset as inactive
      assert %DB.Dataset{is_active: false} = DB.Repo.reload!(dataset)

      verify!(Transport.HTTPoison.Mock)
      verify!(Transport.EmailSender.Mock)
    end

    test "sends an email when a dataset is now archived" do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

      insert(:dataset, is_active: true)

      # dataset is now archived on data.gouv.fr
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, "https://demo.data.gouv.fr/api/1/datasets/123/", "", [], [follow_redirect: true] ->
        archived = DateTime.utc_now() |> DateTime.add(-10, :hour) |> DateTime.to_string()
        # the dataset is not found on datagouv
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"archived" => archived})}}
      end)

      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données archivés"
        assert body =~ ~r/Certains jeux de données sont indiqués comme archivés/
        :ok
      end)

      Transport.DataChecker.inactive_data()

      verify!(Transport.HTTPoison.Mock)
      verify!(Transport.EmailSender.Mock)
    end

    test "does not send email if nothing has disappeared or reappeared" do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

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
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

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
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

      dataset_slug = "reseau-de-transport-de-la-ville"
      producer_email = "hello@example.com"

      dataset = insert(:dataset, is_active: true, slug: dataset_slug)
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

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, 2, fn ->
        [
          %Transport.Notifications.Item{
            reason: :expiration,
            dataset_slug: dataset_slug,
            emails: [producer_email],
            extra_delays: []
          }
        ]
      end)

      # a first mail to our team
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == "deploiement@transport.beta.gouv.fr"
        assert subject == "Jeux de données arrivant à expiration"
        assert body =~ ~r/Jeux de données expirant demain:/
        :ok
      end)

      # a second mail to contact
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _from_name, from_email, to_email, _reply_to, subject, body, _html_body ->
        assert from_email == "contact@transport.beta.gouv.fr"
        assert to_email == producer_email
        assert subject == "Jeu de données arrivant à expiration"
        assert body =~ ~r/Une ressource associée au jeu de données expire demain/
        :ok
      end)

      Transport.DataChecker.outdated_data()

      verify!(Transport.Notifications.FetcherMock)
      verify!(Transport.EmailSender.Mock)
    end

    test "outdated_data job with nothing to send should not send email" do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> nil end)

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            reason: :expiration,
            dataset_slug: "reseau-de-transport-de-la-ville",
            emails: ["hello@example.com"],
            extra_delays: []
          }
        ]
      end)

      Transport.DataChecker.outdated_data()

      verify!(Transport.Notifications.FetcherMock)
      verify!(Transport.EmailSender.Mock)
    end
  end

  describe "send_outdated_data_notifications" do
    test "with a default delay" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr",
                               "contact@transport.beta.gouv.fr",
                               "foo@example.com" = _to,
                               "contact@transport.beta.gouv.fr",
                               "Jeu de données arrivant à expiration" = _subject,
                               plain_text_body,
                               "" = _html_part ->
        assert plain_text_body =~ ~r/Bonjour/
        :ok
      end)

      dataset_slug = "slug"

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: dataset_slug,
            emails: ["foo@example.com"],
            reason: :expiration,
            extra_delays: []
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, datagouv_title: "title"}

      Transport.DataChecker.send_outdated_data_notifications({7, [dataset]})

      verify!(Transport.EmailSender.Mock)
    end

    test "with a matching extra delay" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn _, _, "foo@example.com" = _to, _, _, _, _ -> :ok end)

      dataset_slug = "slug"
      custom_delay = 30

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: dataset_slug,
            emails: ["foo@example.com"],
            reason: :expiration,
            extra_delays: [custom_delay]
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, datagouv_title: "title"}

      Transport.DataChecker.send_outdated_data_notifications({custom_delay, [dataset]})
    end

    test "with a non-matching extra delay" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> :ok end)

      dataset_slug = "slug"

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: dataset_slug,
            emails: ["foo@example.com"],
            reason: :expiration,
            extra_delays: [30]
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, datagouv_title: "title"}

      Transport.DataChecker.send_outdated_data_notifications({42, [dataset]})
    end
  end

  describe "send_new_dataset_notifications" do
    test "no datasets" do
      assert Transport.DataChecker.send_new_dataset_notifications([]) == :ok
    end

    test "with datasets" do
      Transport.EmailSender.Mock
      |> expect(:send_mail, fn "transport.data.gouv.fr",
                               "contact@transport.beta.gouv.fr",
                               "foo@example.com" = _to,
                               "contact@transport.beta.gouv.fr",
                               "Nouveaux jeux de données référencés" = _subject,
                               plain_text_body,
                               "" = _html_part ->
        assert plain_text_body =~ ~r/^Bonjour/

        assert plain_text_body =~
                 "* Super JDD - (Transport public collectif - horaires théoriques) - http://127.0.0.1:5100/datasets/slug"

        :ok
      end)

      dataset_slug = "slug"

      Transport.Notifications.FetcherMock
      |> expect(:fetch_config!, fn ->
        [
          %Transport.Notifications.Item{
            dataset_slug: nil,
            emails: ["foo@example.com"],
            reason: :new_dataset,
            extra_delays: []
          }
        ]
      end)

      dataset = %DB.Dataset{slug: dataset_slug, custom_title: "Super JDD", type: "public-transit"}

      Transport.DataChecker.send_new_dataset_notifications([dataset])

      verify!(Transport.EmailSender.Mock)
    end
  end

  test "possible_delays" do
    Transport.Notifications.FetcherMock
    |> expect(:fetch_config!, fn ->
      [
        %Transport.Notifications.Item{
          dataset_slug: "slug",
          emails: ["foo@example.com"],
          reason: :expiration,
          extra_delays: [14, 30]
        },
        %Transport.Notifications.Item{
          dataset_slug: "other",
          emails: ["foo@example.com"],
          reason: :expiration,
          extra_delays: [30, 42]
        }
      ]
    end)

    assert [0, 7, 14, 30, 42] == Transport.DataChecker.possible_delays()
  end
end
