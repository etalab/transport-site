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

    resource_1 =
      insert(:resource,
        dataset: dataset,
        format: "geojson",
        title: "GeoJSON 1",
        url: "https://static.data.gouv.fr/file.geojson"
      )

    resource_2 =
      insert(:resource,
        dataset: dataset,
        format: "geojson",
        title: "GeoJSON 2",
        url: "https://static.data.gouv.fr/other_file.geojson"
      )

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
    insert_notification(%{dataset: dataset, reason: :resource_unavailable, email: already_sent_email})
    # Should be ignored because this is for another reason
    insert_notification(%{dataset: dataset, reason: :expiration, email: "foo@example.com"})
    # Should be ignored because it's for another dataset
    insert_notification(%{dataset: gtfs_dataset, reason: :resource_unavailable, email: "foo@example.com"})
    # Should be ignored because it's too old
    %{dataset: dataset, reason: :resource_unavailable, email: "foo@example.com", inserted_at: add_days(-8)}
    |> insert_notification()

    setup_dataset_response(dataset, resource_1.url, DateTime.utc_now() |> DateTime.add(-6, :hour))

    %DB.Contact{id: already_sent_contact_id} = insert_contact(%{email: already_sent_email})
    %DB.Contact{id: foo_contact_id} = insert_contact(%{email: "foo@example.com"})
    %DB.Contact{id: reuser_contact_id} = insert_contact(%{email: reuser_email = "reuser@example.com"})

    insert(:notification_subscription, %{
      reason: :resource_unavailable,
      source: :admin,
      role: :producer,
      contact_id: already_sent_contact_id,
      dataset_id: dataset.id
    })

    insert(:notification_subscription, %{
      reason: :resource_unavailable,
      source: :admin,
      role: :producer,
      contact_id: foo_contact_id,
      dataset_id: dataset.id
    })

    insert(:notification_subscription, %{
      reason: :resource_unavailable,
      source: :user,
      role: :reuser,
      contact_id: reuser_contact_id,
      dataset_id: dataset.id
    })

    %DB.Contact{id: bar_contact_id} = insert_contact(%{email: "bar@example.com"})

    insert(:notification_subscription, %{
      reason: :resource_unavailable,
      source: :admin,
      role: :producer,
      contact_id: bar_contact_id,
      dataset_id: gtfs_dataset.id
    })

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.data.gouv.fr",
                             "foo@example.com" = _to,
                             "contact@transport.data.gouv.fr",
                             subject,
                             _plain_text_body,
                             html_part ->
      assert subject == "Ressources indisponibles dans le jeu de données #{dataset.custom_title}"

      assert html_part =~
               ~s(Les ressources #{resource_1.title}, #{resource_2.title} dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> ne sont plus disponibles au téléchargement depuis plus de 6h.)

      assert html_part =~ "Il semble que vous ayez supprimé puis créé une nouvelle ressource"

      assert html_part =~
               ~s(rendez-vous sur votre <a href="http://127.0.0.1:5100/espace_producteur">Espace Producteur</a> à partir duquel vous pourrez procéder à ces mises à jour)

      :ok
    end)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.data.gouv.fr",
                             ^reuser_email = _to,
                             "contact@transport.data.gouv.fr",
                             subject,
                             _plain_text_body,
                             html_part ->
      assert subject == "Ressources indisponibles dans le jeu de données #{dataset.custom_title}"

      assert html_part =~
               ~s(Les ressources #{resource_1.title}, #{resource_2.title} du jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">#{dataset.custom_title}</a> que vous réutilisez ne sont plus disponibles au téléchargement depuis plus de 6h.)

      assert html_part =~ "Nous avons déjà informé le producteur de ces données."

      :ok
    end)

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.data.gouv.fr",
                             "bar@example.com" = _to,
                             "contact@transport.data.gouv.fr",
                             subject,
                             _plain_text_body,
                             html_part ->
      assert subject == "Ressources indisponibles dans le jeu de données #{gtfs_dataset.custom_title}"

      assert html_part =~
               ~s(Les ressources #{resource_gtfs.title} dans votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{gtfs_dataset.slug}">#{gtfs_dataset.custom_title}</a> ne sont plus disponibles au téléchargement depuis plus de 6h.)

      refute html_part =~ "Il semble que vous ayez supprimé puis créé une nouvelle ressource"

      assert html_part =~
               "Nous vous invitons à corriger l’accès à vos données dès que possible afin de ne pas perturber leur réutilisation."

      :ok
    end)

    assert :ok == perform_job(ResourceUnavailableNotificationJob, %{})

    # Logs have been saved
    recent_dt = DateTime.utc_now() |> DateTime.add(-1, :second)

    assert DB.Notification |> DB.Repo.aggregate(:count) == 7

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
             n.email_hash == ^reuser_email and n.dataset_id == ^dataset_id and n.inserted_at >= ^recent_dt and
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

  test "notifications_sent_recently" do
    dataset = insert(:dataset)

    %{dataset: dataset, reason: :resource_unavailable, email: "foo@example.com", inserted_at: add_days(-6)}
    |> insert_notification()

    # Too old
    %{dataset: dataset, reason: :resource_unavailable, email: "bar@example.com", inserted_at: add_days(-8)}
    |> insert_notification()

    # Another reason
    %{dataset: dataset, reason: :expiration, email: "baz@example.com", inserted_at: add_days(-6)}
    |> insert_notification()

    assert MapSet.new(["foo@example.com"]) == ResourceUnavailableNotificationJob.notifications_sent_recently(dataset)
  end

  defp add_days(days), do: DateTime.utc_now() |> DateTime.add(days, :day)

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
