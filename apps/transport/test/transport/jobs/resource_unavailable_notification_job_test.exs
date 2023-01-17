defmodule Transport.Test.Transport.Jobs.ResourceUnavailableNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  alias Transport.Jobs.ResourceUnavailableNotificationJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "relevant_unavailabilities" do
    dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)
    gtfs_resource = insert(:resource, dataset: dataset, format: "GTFS")

    other_dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true)
    geojson_resource = insert(:resource, dataset: other_dataset, format: "geojson")

    assert %{} == ResourceUnavailableNotificationJob.relevant_unavailabilities(DateTime.utc_now())

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
             |> Map.keys()
             |> Enum.map(& &1.id)
  end

  test "perform" do
    # 2 datasets in scope: 1 GTFS dataset with a resource, another dataset with 2 resources
    # All resources are currently down for [6h00 ; 6h30]
    %{id: dataset_id} = dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")

    %{id: gtfs_dataset_id} =
      gtfs_dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Dataset GTFS")

    resource_1 = insert(:resource, dataset: dataset, format: "geojson", title: "GeoJSON 1")
    resource_2 = insert(:resource, dataset: dataset, format: "geojson", title: "GeoJSON 2")
    resource_gtfs = insert(:resource, dataset: gtfs_dataset, format: "GTFS")

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
    insert_notification(%{dataset_id: dataset_id, reason: :resource_unavailable, email: already_sent_email})
    # Should be ignored because this is for another reason
    insert_notification(%{dataset_id: dataset_id, reason: :expiration, email: "foo@example.com"})
    # Should be ignored because it's for another dataset
    insert_notification(%{dataset_id: gtfs_dataset_id, reason: :resource_unavailable, email: "foo@example.com"})
    # Should be ignored because it's too old
    %{dataset_id: dataset_id, reason: :resource_unavailable, email: "foo@example.com"}
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
               "#{resource_1.title} — http://127.0.0.1:5100/resources/#{resource_1.id}"

      assert plain_text_body =~
               "#{resource_2.title} — http://127.0.0.1:5100/resources/#{resource_2.id}"

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
               "#{resource_gtfs.title} — http://127.0.0.1:5100/resources/#{resource_gtfs.id}"

      :ok
    end)

    assert :ok == perform_job(ResourceUnavailableNotificationJob, %{})

    # Logs have been saved
    recent_dt = DateTime.utc_now() |> DateTime.add(-1, :second)

    assert DB.Notification
           |> where(
             [n],
             n.email_hash == ^"foo@example.com" and n.dataset_id == ^dataset_id and n.inserted_at >= ^recent_dt and
               n.reason == :resource_unavailable
           )
           |> DB.Repo.exists?()

    assert DB.Notification
           |> where(
             [n],
             n.email_hash == ^"bar@example.com" and n.dataset_id == ^gtfs_dataset_id and n.inserted_at >= ^recent_dt and
               n.reason == :resource_unavailable
           )
           |> DB.Repo.exists?()
  end
end
