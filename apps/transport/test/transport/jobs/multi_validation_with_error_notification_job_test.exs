defmodule Transport.Test.Transport.Jobs.MultiValidationWithErrorNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  alias Transport.Jobs.MultiValidationWithErrorNotificationJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "relevant_validations" do
    dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)
    geojson_resource = insert(:resource, dataset: dataset, format: "geojson")

    rh_geojson_resource = insert(:resource_history, resource: geojson_resource)

    insert(:multi_validation, %{
      validator: Transport.Validators.GTFSRT.validator_name(),
      resource: insert(:resource, dataset: dataset, format: "gtfs-rt"),
      max_error: "ERROR"
    })

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

    refute Enum.empty?(
             MultiValidationWithErrorNotificationJob.relevant_validations(
               DateTime.utc_now()
               |> DateTime.add(-30, :minute)
             )
           )
  end

  test "perform" do
    # 2 datasets in scope, with different validators
    # 1 GTFS dataset with a resource, another dataset with a JSON schema and 2 errors
    %{id: dataset_id} = dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")

    %{id: gtfs_dataset_id} =
      gtfs_dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Dataset GTFS")

    resource_1 = insert(:resource, dataset: dataset, format: "geojson", title: "GeoJSON 1")
    resource_2 = insert(:resource, dataset: dataset, format: "geojson", title: "GeoJSON 2")
    resource_gtfs = insert(:resource, dataset: gtfs_dataset, format: "GTFS")
    rh_resource_1 = insert(:resource_history, resource: resource_1)
    rh_resource_2 = insert(:resource_history, resource: resource_2)
    rh_resource_gtfs = insert(:resource_history, resource: resource_gtfs)

    insert(:multi_validation, %{
      resource_history: rh_resource_1,
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: rh_resource_2,
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: rh_resource_gtfs,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      max_error: "Fatal"
    })

    already_sent_email = "alreadysent@example.fr"
    insert_notification(%{dataset: dataset, reason: :dataset_with_error, email: already_sent_email})
    # Should be ignored because this is for another reason
    insert_notification(%{dataset: dataset, reason: :expiration, email: "foo@example.com"})
    # Should be ignored because it's for another dataset
    insert_notification(%{dataset: gtfs_dataset, reason: :dataset_with_error, email: "foo@example.com"})
    # Should be ignored because it's too old
    %{dataset: dataset, reason: :dataset_with_error, email: "foo@example.com"}
    |> insert_notification()
    |> Ecto.Changeset.change(%{inserted_at: DateTime.utc_now() |> DateTime.add(-20, :day)})
    |> DB.Repo.update!()

    Transport.Notifications.FetcherMock
    |> expect(:fetch_config!, 2, fn ->
      [
        %Transport.Notifications.Item{
          dataset_slug: dataset.slug,
          emails: ["foo@example.com", already_sent_email],
          reason: :expiration,
          extra_delays: []
        },
        %Transport.Notifications.Item{
          dataset_slug: gtfs_dataset.slug,
          emails: ["bar@example.com"],
          reason: :expiration,
          extra_delays: []
        }
      ]
    end)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "foo@example.com" = _to,
                             "contact@transport.beta.gouv.fr",
                             subject,
                             plain_text_body,
                             "" = _html_part ->
      assert subject == "Erreurs détectées dans le jeu de données #{dataset.custom_title}"

      assert plain_text_body =~
               "Des erreurs bloquantes ont été détectées dans votre jeu de données #{dataset.custom_title}"

      assert plain_text_body =~
               "#{resource_1.title} — http://127.0.0.1:5100/resources/#{resource_1.id}#validation-report"

      assert plain_text_body =~
               "#{resource_2.title} — http://127.0.0.1:5100/resources/#{resource_2.id}#validation-report"

      :ok
    end)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "bar@example.com" = _to,
                             "contact@transport.beta.gouv.fr",
                             subject,
                             plain_text_body,
                             "" = _html_part ->
      assert subject == "Erreurs détectées dans le jeu de données #{gtfs_dataset.custom_title}"

      assert plain_text_body =~
               "Des erreurs bloquantes ont été détectées dans votre jeu de données #{gtfs_dataset.custom_title}"

      assert plain_text_body =~
               "#{resource_gtfs.title} — http://127.0.0.1:5100/resources/#{resource_gtfs.id}#validation-report"

      :ok
    end)

    assert :ok == perform_job(MultiValidationWithErrorNotificationJob, %{})

    # Logs have been saved
    recent_dt = DateTime.utc_now() |> DateTime.add(-1, :second)

    assert DB.Notification
           |> where(
             [n],
             n.email_hash == ^"foo@example.com" and n.dataset_id == ^dataset_id and n.inserted_at >= ^recent_dt and
               n.reason == :dataset_with_error
           )
           |> DB.Repo.exists?()

    assert DB.Notification
           |> where(
             [n],
             n.email_hash == ^"bar@example.com" and n.dataset_id == ^gtfs_dataset_id and n.inserted_at >= ^recent_dt and
               n.reason == :dataset_with_error
           )
           |> DB.Repo.exists?()
  end
end
