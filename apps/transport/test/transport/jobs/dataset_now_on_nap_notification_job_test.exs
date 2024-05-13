defmodule Transport.Test.Transport.Jobs.DatasetNowOnNAPNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  import Mox
  alias Transport.Jobs.DatasetNowOnNAPNotificationJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    %{id: dataset_id} = dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")

    # We already sent a notification to someone for this dataset, it should be ignored
    insert_notification(%{
      dataset: dataset,
      reason: :dataset_now_on_nap,
      email: already_sent_email = Ecto.UUID.generate() <> "@example.fr"
    })

    %DB.Contact{email: email} = contact = insert_contact()

    ~w(resource_unavailable expiration)a
    |> Enum.each(fn reason ->
      insert(:notification_subscription, %{
        reason: reason,
        source: :admin,
        role: :producer,
        contact: contact,
        dataset: dataset
      })
    end)

    # Should be ignored, it's a reuser
    insert(:notification_subscription, %{
      reason: :expiration,
      source: :user,
      role: :reuser,
      contact: insert_contact(),
      dataset: dataset
    })

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.data.gouv.fr",
                             ^email,
                             "contact@transport.data.gouv.fr",
                             "Votre jeu de données a été référencé sur transport.data.gouv.fr",
                             "",
                             html_content ->
      assert html_content =~
               ~s(Votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">Mon JDD</a> a bien été référencé)

      assert html_content =~
               ~s(Rendez-vous sur votre <a href="http://127.0.0.1:5100/espace_producteur?utm_source=transactional_email&amp;utm_medium=email&amp;utm_campaign=dataset_now_on_nap">Espace Producteur</a)

      :ok
    end)

    assert :ok == perform_job(DatasetNowOnNAPNotificationJob, %{"dataset_id" => dataset_id})

    # Logs have been saved
    assert [
             %DB.Notification{reason: :dataset_now_on_nap, dataset_id: ^dataset_id, email: ^already_sent_email},
             %DB.Notification{reason: :dataset_now_on_nap, dataset_id: ^dataset_id, email: ^email}
           ] = DB.Notification |> order_by([n], asc: n.inserted_at) |> DB.Repo.all()
  end
end
