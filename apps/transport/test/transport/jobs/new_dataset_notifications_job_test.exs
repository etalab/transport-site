defmodule Transport.Test.Transport.Jobs.NewDatasetNotificationsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Transport.Jobs.NewDatasetNotificationsJob

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "relevant_datasets" do
    %{id: d1_id} = insert(:dataset, inserted_at: hours_ago(23), is_active: true)
    %{id: d2_id} = insert(:dataset, inserted_at: hours_ago(1), is_active: true)
    insert(:dataset, inserted_at: hours_ago(25), is_active: true)
    insert(:dataset, inserted_at: hours_ago(5), is_active: false)

    assert [%DB.Dataset{id: ^d1_id}, %DB.Dataset{id: ^d2_id}] =
             DateTime.utc_now() |> NewDatasetNotificationsJob.relevant_datasets() |> Enum.sort(&(&1.id < &2.id))
  end

  test "perform" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, inserted_at: hours_ago(23), is_active: true)
    %DB.Contact{id: contact_id, email: email} = insert_contact()
    insert(:notification_subscription, %{reason: :new_dataset, source: :admin, contact_id: contact_id})

    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             ^email = _to,
                             "contact@transport.beta.gouv.fr",
                             "Nouveaux jeux de données référencés" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body =~ ~r/Bonjour/
      :ok
    end)

    assert :ok == perform_job(NewDatasetNotificationsJob, %{}, inserted_at: DateTime.utc_now())

    # Logs have been saved
    assert [%DB.Notification{email: ^email, reason: :new_dataset, dataset_id: ^dataset_id}] =
             DB.Notification |> DB.Repo.all()
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours * 60 * 60, :second)
  end
end
