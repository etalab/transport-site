defmodule Transport.Test.Transport.Jobs.NewCommentsNotificationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Swoosh.TestAssertions
  alias Transport.Jobs.NewCommentsNotificationJob

  setup :verify_on_exit!

  doctest NewCommentsNotificationJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "relevant_datasets" do
    test "a weekday excluding Monday" do
      # Ignored: inactive
      insert(:dataset,
        is_active: false,
        is_hidden: false,
        latest_data_gouv_comment_timestamp: ~U[2024-03-27 10:00:00.00Z]
      )

      # Ignored: hidden
      insert(:dataset,
        is_active: true,
        is_hidden: true,
        latest_data_gouv_comment_timestamp: ~U[2024-03-27 12:00:00.00Z]
      )

      # Ignored: more than a day old
      insert(:dataset,
        is_active: true,
        is_hidden: false,
        latest_data_gouv_comment_timestamp: ~U[2024-03-27 08:00:00.00Z]
      )

      %DB.Dataset{id: dataset_id} =
        insert(:dataset,
          is_active: true,
          is_hidden: false,
          latest_data_gouv_comment_timestamp: ~U[2024-03-27 10:00:00.00Z]
        )

      assert [%DB.Dataset{id: ^dataset_id}] =
               ~U[2024-03-28 09:00:00.00Z] |> NewCommentsNotificationJob.relevant_datasets_query() |> DB.Repo.all()
    end

    test "on a Monday" do
      # Ignored: inactive
      insert(:dataset,
        is_active: false,
        is_hidden: false,
        latest_data_gouv_comment_timestamp: ~U[2024-03-30 10:00:00.00Z]
      )

      # Ignored: hidden
      insert(:dataset,
        is_active: true,
        is_hidden: true,
        latest_data_gouv_comment_timestamp: ~U[2024-03-30 12:00:00.00Z]
      )

      # Ignored: more than 3 days old
      insert(:dataset,
        is_active: true,
        is_hidden: false,
        latest_data_gouv_comment_timestamp: ~U[2024-03-29 08:00:00.00Z]
      )

      %DB.Dataset{id: dataset_id} =
        insert(:dataset,
          is_active: true,
          is_hidden: false,
          latest_data_gouv_comment_timestamp: ~U[2024-03-29 10:00:00.00Z]
        )

      %DB.Dataset{id: other_dataset_id} =
        insert(:dataset,
          is_active: true,
          is_hidden: false,
          latest_data_gouv_comment_timestamp: ~U[2024-03-29 10:00:00.00Z]
        )

      assert [%DB.Dataset{id: ^dataset_id}, %DB.Dataset{id: ^other_dataset_id}] =
               ~U[2024-04-01 09:00:00.00Z]
               |> NewCommentsNotificationJob.relevant_datasets_query()
               |> DB.Repo.all()
               |> Enum.sort_by(& &1.id)
    end
  end

  test "relevant_contacts" do
    %DB.Contact{id: contact_id} = contact = insert_contact()
    producer_contact = insert_contact()
    follower_only_contact = insert_contact()
    dataset = insert(:dataset, latest_data_gouv_comment_timestamp: ~U[2024-03-27 10:00:00.00Z])

    insert(:dataset_follower, dataset_id: dataset.id, contact_id: contact_id, source: :datagouv)
    insert(:notification_subscription, contact: contact, source: :user, reason: :daily_new_comments, role: :reuser)

    # `producer_contact` is subscribed and does not follow the dataset
    insert(:notification_subscription,
      contact: producer_contact,
      source: :user,
      reason: :daily_new_comments,
      role: :producer
    )

    # `follower_only_contact` follows the dataset but is not subscribed for the relevant reason
    insert(:dataset_follower, dataset_id: dataset.id, contact_id: follower_only_contact.id, source: :datagouv)

    insert(:notification_subscription,
      contact: follower_only_contact,
      dataset: dataset,
      source: :user,
      reason: :expiration,
      role: :reuser
    )

    assert [%DB.Contact{id: ^contact_id}] = NewCommentsNotificationJob.relevant_contacts(~U[2024-03-28 09:00:00.00Z])
  end

  test "enqueues jobs" do
    %DB.Contact{id: contact_id} = contact = insert_contact()

    %DB.Dataset{id: dataset_id} =
      insert(:dataset, latest_data_gouv_comment_timestamp: ~U[2024-03-27 10:00:00.00Z])

    insert(:dataset_follower, dataset_id: dataset_id, contact_id: contact_id, source: :datagouv)
    insert(:notification_subscription, contact: contact, source: :user, reason: :daily_new_comments, role: :reuser)

    assert :ok == perform_job(NewCommentsNotificationJob, %{}, scheduled_at: ~U[2024-03-28 09:00:00.00Z])

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.NewCommentsNotificationJob",
               args: %{"contact_id" => ^contact_id, "dataset_ids" => [^dataset_id]}
             }
           ] = all_enqueued()
  end

  test "perform for a single contact" do
    %DB.Contact{id: contact_id, email: email} = insert_contact()
    other_followed_dataset = insert(:dataset)

    %DB.Dataset{id: dataset1_id} =
      dataset1 =
      insert(:dataset, latest_data_gouv_comment_timestamp: ~U[2024-03-29 10:00:00.00Z])

    %DB.Dataset{id: dataset2_id} =
      dataset2 =
      insert(:dataset, latest_data_gouv_comment_timestamp: ~U[2024-03-29 10:00:00.00Z])

    %DB.Dataset{id: other_dataset_id} =
      insert(:dataset, latest_data_gouv_comment_timestamp: ~U[2024-03-29 10:00:00.00Z])

    # Identifies two datasets as relevant
    assert [%DB.Dataset{id: ^dataset1_id}, %DB.Dataset{id: ^dataset2_id}, %DB.Dataset{id: ^other_dataset_id}] =
             ~U[2024-04-01 09:00:00.00Z]
             |> NewCommentsNotificationJob.relevant_datasets_query()
             |> DB.Repo.all()
             |> Enum.sort_by(& &1.id)

    insert(:dataset_follower, dataset_id: dataset1_id, contact_id: contact_id, source: :datagouv)
    insert(:dataset_follower, dataset_id: dataset2_id, contact_id: contact_id, source: :datagouv)
    insert(:dataset_follower, dataset_id: other_followed_dataset.id, contact_id: contact_id, source: :datagouv)

    # Perform the job for a single contact
    assert :ok ==
             perform_job(NewCommentsNotificationJob, %{
               "contact_id" => contact_id,
               "dataset_ids" => [dataset1_id, dataset2_id, other_dataset_id]
             })

    # Email has been sent
    assert_email_sent(fn %Swoosh.Email{
                           from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
                           to: [{"", ^email}],
                           reply_to: {"", "contact@transport.data.gouv.fr"},
                           subject: "Nouveaux commentaires sur transport.data.gouv.fr",
                           text_body: nil,
                           html_body: html_body
                         } ->
      assert remove_whitespace(html_body) == remove_whitespace(~s|
      <p>Bonjour,</p>

      <p>
        Des discussions ont eu lieu sur certains jeux de données que vous suivez. Vous pouvez prendre connaissance de ces échanges.
      </p>

      <ul>
        <li>
        <a href="http://127.0.0.1:5100/datasets/#{dataset1.slug}#dataset-discussions">#{dataset1.custom_title}</a>
        </li>
        <li>
        <a href="http://127.0.0.1:5100/datasets/#{dataset2.slug}#dataset-discussions">#{dataset2.custom_title}</a>
        </li>
      </ul>

      <p>L’équipe transport.data.gouv.fr</p>|)
    end)

    # Notifications have been saved
    assert [
             %DB.Notification{reason: :daily_new_comments, dataset_id: ^dataset1_id, email: ^email},
             %DB.Notification{reason: :daily_new_comments, dataset_id: ^dataset2_id, email: ^email}
           ] =
             DB.Notification |> DB.Repo.all()
  end

  defp remove_whitespace(value), do: value |> String.replace(~r/\s/, "") |> String.trim()
end
