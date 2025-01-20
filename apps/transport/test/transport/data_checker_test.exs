defmodule Transport.DataCheckerTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory
  import Swoosh.TestAssertions

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
