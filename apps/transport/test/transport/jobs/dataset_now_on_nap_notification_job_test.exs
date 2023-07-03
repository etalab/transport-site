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

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email,
                             "contact@transport.beta.gouv.fr",
                             "Votre jeu de données a été référencé sur transport.data.gouv.fr",
                             "",
                             html_content ->
      assert html_content =~
               ~s(Votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">Mon JDD</a> a bien été référencé)

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
