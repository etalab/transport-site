defmodule Transport.Test.Transport.Jobs.NewDatasetNotificationsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Swoosh.TestAssertions
  alias Transport.Jobs.NewDatasetNotificationsJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "relevant_datasets" do
    %{id: d1_id} = insert(:dataset, inserted_at: hours_ago(23), is_active: true)
    %{id: d2_id} = insert(:dataset, inserted_at: hours_ago(1), is_active: true)
    # Too old
    insert(:dataset, inserted_at: hours_ago(25), is_active: true)
    # Inactive
    insert(:dataset, inserted_at: hours_ago(5), is_active: false)
    # Hidden
    insert(:dataset, inserted_at: hours_ago(5), is_active: true, is_hidden: true)

    assert [%DB.Dataset{id: ^d1_id}, %DB.Dataset{id: ^d2_id}] =
             DateTime.utc_now() |> NewDatasetNotificationsJob.relevant_datasets() |> Enum.sort(&(&1.id < &2.id))
  end

  test "perform" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, inserted_at: hours_ago(23), is_active: true)
    %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

    %DB.NotificationSubscription{id: ns_id} =
      insert(:notification_subscription, %{reason: :new_dataset, source: :admin, role: :reuser, contact_id: contact_id})

    assert :ok == perform_job(NewDatasetNotificationsJob, %{}, inserted_at: DateTime.utc_now())

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: {DB.Contact.display_name(contact), email},
      subject: "Nouveaux jeux de données référencés",
      text_body: ~r/Bonjour/,
      html_body: nil
    )

    # Logs have been saved
    assert [
             %DB.Notification{
               contact_id: ^contact_id,
               email: ^email,
               reason: :new_dataset,
               dataset_id: nil,
               notification_subscription_id: ^ns_id,
               payload: %{"dataset_ids" => [^dataset_id]}
             }
           ] =
             DB.Notification |> DB.Repo.all()
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours * 60 * 60, :second)
  end
end
