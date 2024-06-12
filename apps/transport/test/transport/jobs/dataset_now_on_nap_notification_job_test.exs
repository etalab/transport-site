defmodule Transport.Test.Transport.Jobs.DatasetNowOnNAPNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Ecto.Query
  alias Transport.Jobs.DatasetNowOnNAPNotificationJob
  import Swoosh.TestAssertions

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    %{id: dataset_id} = dataset = insert(:dataset, slug: Ecto.UUID.generate(), is_active: true, custom_title: "Mon JDD")

    # We already sent a notification to someone for this dataset, it should be ignored
    insert_notification(%{
      dataset: dataset,
      reason: :dataset_now_on_nap,
      role: :producer,
      email: already_sent_email = Ecto.UUID.generate() <> "@example.fr"
    })

    %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

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

    assert :ok == perform_job(DatasetNowOnNAPNotificationJob, %{"dataset_id" => dataset_id})

    html_content =
      ~s(Votre jeu de données <a href="http://127.0.0.1:5100/datasets/#{dataset.slug}">Mon JDD</a> a bien été référencé)

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: [{DB.Contact.display_name(contact), email}],
      reply_to: {"", "contact@transport.data.gouv.fr"},
      subject: "Votre jeu de données a été référencé sur transport.data.gouv.fr",
      text_body: nil,
      html_body: ~r/#{html_content}/
    )

    # Logs have been saved
    assert [
             %DB.Notification{
               reason: :dataset_now_on_nap,
               role: :producer,
               dataset_id: ^dataset_id,
               email: ^already_sent_email,
               notification_subscription_id: nil
             },
             %DB.Notification{
               reason: :dataset_now_on_nap,
               role: :producer,
               dataset_id: ^dataset_id,
               email: ^email,
               notification_subscription_id: nil,
               contact_id: ^contact_id
             }
           ] = DB.Notification |> order_by([n], asc: n.inserted_at) |> DB.Repo.all()
  end
end
