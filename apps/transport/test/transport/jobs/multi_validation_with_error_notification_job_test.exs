defmodule Transport.Test.Transport.Jobs.MultiValidationWithErrorNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
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
      resource_id: rh_geojson_resource.resource_id,
      result: %{"has_errors" => true},
      inserted_at: DateTime.utc_now() |> DateTime.add(-45, :minute)
    })

    # Should be empty because:
    # - real-time validations (for GTFS-RT) are ignored
    # - the GeoJSON is too old (45 minutes)
    assert %{} == MultiValidationWithErrorNotificationJob.relevant_validations(DateTime.utc_now())

    refute Enum.empty?(MultiValidationWithErrorNotificationJob.relevant_validations(DateTime.utc_now() |> DateTime.add(-30, :minute)))
  end

  test "perform" do
    # 2 datasets in scope, with different validators
    # 1 GTFS dataset with a resource, another dataset with a JSON schema and 2 errors
    dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")
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
      resource_id: rh_resource_1.resource_id,
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: rh_resource_2,
      validator: Transport.Validators.EXJSONSchema.validator_name(),
      resource_id: rh_resource_2.resource_id,
      result: %{"has_errors" => true}
    })

    insert(:multi_validation, %{
      resource_history: rh_resource_gtfs,
      validator: Transport.Validators.GTFSTransport.validator_name(),
      resource_id: rh_resource_gtfs.resource_id,
      max_error: "Fatal"
    })

    Transport.Notifications.FetcherMock
    |> expect(:fetch_config!, 2, fn ->
      [
        %Transport.Notifications.Item{
          dataset_slug: dataset.slug,
          emails: ["foo@example.com"],
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
                             "Erreur de validation détectée" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ "Le contenu du jeu de données #{dataset.custom_title} vient de changer"
      assert plain_text_body =~ "#{resource_1.title} - http://127.0.0.1:5100/resources/#{resource_1.id}#validation-report"
      assert plain_text_body =~ "#{resource_2.title} - http://127.0.0.1:5100/resources/#{resource_2.id}#validation-report"
      :ok
    end)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "bar@example.com" = _to,
                             "contact@transport.beta.gouv.fr",
                             "Erreur de validation détectée" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ "Le contenu du jeu de données #{gtfs_dataset.custom_title} vient de changer"
      assert plain_text_body =~ "#{resource_gtfs.title} - http://127.0.0.1:5100/resources/#{resource_gtfs.id}#validation-report"
      :ok
    end)

    assert :ok == perform_job(MultiValidationWithErrorNotificationJob, %{})
  end
end
