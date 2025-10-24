defmodule Transport.CommentsCheckerTest do
  use ExUnit.Case, async: false
  alias DB.{Dataset, Repo}
  alias Transport.CommentsChecker
  import DB.Factory
  import Mock
  import Mox
  import Swoosh.TestAssertions
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def assert_dataset_ts(id, timestamp) do
    %{latest_data_gouv_comment_timestamp: db_ts} = Dataset |> Repo.get!(id)

    case timestamp do
      nil -> assert is_nil(db_ts)
      %DateTime{} = timestamp -> assert DateTime.diff(timestamp, db_ts) < 1
    end
  end

  test "relevant_datasets" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, is_active: true)
    insert(:dataset, is_active: true, is_hidden: true)
    insert(:dataset, is_active: false)

    assert [%DB.Dataset{id: ^dataset_id}] = CommentsChecker.relevant_datasets()
  end

  test "check for new comments on data.gouv.fr" do
    %DB.Dataset{id: dataset_id} = insert(:dataset, datagouv_title: "dataset 1")
    %DB.Contact{id: contact_id, email: email} = contact = insert_contact()

    %DB.NotificationSubscription{id: ns_id} =
      insert(:notification_subscription, %{
        reason: :daily_new_comments,
        source: :admin,
        contact_id: contact_id,
        role: :producer
      })

    # Should be ignored: reuser
    insert(:notification_subscription, %{
      reason: :daily_new_comments,
      source: :user,
      contact_id: insert_contact().id,
      role: :reuser
    })

    # when the dataset is created, no comment timestamp is stored
    assert_dataset_ts(dataset_id, nil)

    get_mock = fn _url, [], _ ->
      {:ok,
       %{
         "data" => [
           %{
             "id" => "discussion_id_1",
             "discussion" => [
               %{"posted_on" => "2020-01-01T12:00:00.000100+00:00", "content" => "commentaire 1"}
             ]
           }
         ]
       }}
    end

    with_mock Datagouvfr.Client.API, get: get_mock do
      number_new_comments = CommentsChecker.check_for_new_comments()

      assert_email_sent(
        subject: "1 nouveaux commentaires sur transport.data.gouv.fr",
        to: [{DB.Contact.display_name(contact), contact.email}]
      )

      assert number_new_comments == 1
      assert_dataset_ts(dataset_id, ~U[2020-01-01T12:00:00.000100Z])
    end

    # second run: we shouldn't find new comment
    with_mock Datagouvfr.Client.API, get: get_mock do
      number_new_comments = CommentsChecker.check_for_new_comments()

      assert_no_email_sent()

      assert number_new_comments == 0
      assert_dataset_ts(dataset_id, ~U[2020-01-01T12:00:00.000100Z])
    end

    # we add a new comment
    get_mock = fn _url, [], _ ->
      {:ok,
       %{
         "data" => [
           %{
             "id" => "discussion_id_1",
             "discussion" => [
               %{"posted_on" => "2020-01-01T12:00:00.000100+00:00", "content" => "commentaire 1"},
               %{"posted_on" => "2021-01-01T12:00:00.000200+00:00", "content" => "commentaire 2"}
             ]
           }
         ]
       }}
    end

    with_mock Datagouvfr.Client.API, get: get_mock do
      number_new_comments = CommentsChecker.check_for_new_comments()

      assert_email_sent(
        subject: "1 nouveaux commentaires sur transport.data.gouv.fr",
        to: [{DB.Contact.display_name(contact), contact.email}]
      )

      assert number_new_comments == 1
      assert_dataset_ts(dataset_id, ~U[2021-01-01T12:00:00.000200Z])
    end

    # Logs have been saved
    assert [
             %DB.Notification{
               reason: :daily_new_comments,
               role: :producer,
               dataset_id: nil,
               contact_id: ^contact_id,
               email: ^email,
               notification_subscription_id: ^ns_id,
               payload: %{"dataset_ids" => [^dataset_id]}
             },
             %DB.Notification{
               reason: :daily_new_comments,
               role: :producer,
               dataset_id: nil,
               contact_id: ^contact_id,
               email: ^email,
               notification_subscription_id: ^ns_id,
               payload: %{"dataset_ids" => [^dataset_id]}
             }
           ] = DB.Notification |> DB.Repo.all()
  end

  test "does not insert notification logs when there are no new comments" do
    latest_ts = DateTime.utc_now()
    %{datagouv_id: datagouv_id} = insert(:dataset, latest_data_gouv_comment_timestamp: latest_ts)

    Transport.HTTPoison.Mock
    |> expect(:request, 2, fn :get,
                              "https://demo.data.gouv.fr/api/1/discussions/",
                              "",
                              [],
                              [follow_redirect: true, params: %{for: ^datagouv_id}] ->
      data = %{
        "data" => [
          %{
            "id" => "discussion_id_1",
            "discussion" => [
              %{"posted_on" => DateTime.to_string(latest_ts), "content" => "commentaire 1"}
            ]
          }
        ]
      }

      {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(data)}}
    end)

    assert [{%Dataset{datagouv_id: ^datagouv_id}, ^datagouv_id, _title, [] = _comments}] =
             CommentsChecker.fetch_new_comments()

    number_new_comments = CommentsChecker.check_for_new_comments()

    assert number_new_comments == 0
    assert [] == DB.Notification |> DB.Repo.all()
  end

  test "get latest comment timestamp" do
    discussions = [
      %{"posted_on" => "2020-05-12T15:07:04.547000+00:00"},
      %{"posted_on" => "2021-05-12T15:07:00.547000+00:00"},
      %{"posted_on" => "2021-05-12T15:07:04.547000+00:00"},
      %{"posted_on" => "2021-05-12T15:06:48.512000+00:00"}
    ]

    assert CommentsChecker.comments_latest_timestamp(discussions) ==
             ~U[2021-05-12 15:07:04Z]
  end

  test "timestamp of empty list is nil" do
    assert is_nil(CommentsChecker.comments_latest_timestamp([]))
  end

  test "timestamp of nil is nil" do
    assert is_nil(CommentsChecker.comments_latest_timestamp(nil))
  end

  test "fetch comments for datasets posted after timestamp" do
    discussions = [
      %{"discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000+00:00", "content" => "commentaire 1"}]},
      %{
        "discussion" => [
          %{"posted_on" => "2020-05-12T15:07:00.547000+00:00", "content" => "commentaire 2"},
          %{"posted_on" => "2022-05-12T15:07:04.547000+00:00", "content" => "commentaire 3"}
        ]
      },
      %{"discussion" => [%{"posted_on" => "2022-05-12T15:06:48.512000+00:00", "content" => "commentaire 4"}]}
    ]

    selected_discussions = CommentsChecker.comments_posted_after(discussions, ~U[2022-01-01 00:00:00.000Z])

    assert selected_discussions |> Enum.frequencies_by(fn d -> d["content"] end) == %{
             "commentaire 3" => 1,
             "commentaire 4" => 1
           }

    selected_discussions_empty = CommentsChecker.comments_posted_after(discussions, ~U[2023-01-01 00:00:00.000Z])
    assert selected_discussions_empty == []
  end

  test "comments_posted_after with nil timestamp" do
    discussions = [
      %{"discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000+00:00", "content" => "commentaire 1"}]},
      %{
        "discussion" => [
          %{"posted_on" => "2020-05-12T15:07:00.547000+00:00", "content" => "commentaire 2"},
          %{"posted_on" => "2022-05-12T15:07:04.547000+00:00", "content" => "commentaire 3"}
        ]
      },
      %{"discussion" => [%{"posted_on" => "2022-05-12T15:06:48.512000+00:00", "content" => "commentaire 4"}]}
    ]

    assert discussions |> CommentsChecker.comments_posted_after(nil) |> Enum.count() == 4
    assert CommentsChecker.comments_posted_after([], nil) == []
  end

  test "comments_posted_after with empty discussions" do
    assert CommentsChecker.comments_posted_after([], ~U[2023-01-01 00:00:00.000Z]) == []
  end

  test "add a discussion id to comments" do
    discussions = [
      %{
        "id" => "id1",
        "discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000+00:00", "content" => "commentaire 1"}]
      },
      %{
        "id" => "id2",
        "discussion" => [
          %{"posted_on" => "2020-05-12T15:07:00.547000+00:00", "content" => "commentaire 2"},
          %{"posted_on" => "2022-05-12T15:07:04.547000+00:00", "content" => "commentaire 3"}
        ]
      }
    ]

    modified_discussions = CommentsChecker.add_discussion_id_to_comments(discussions)

    assert modified_discussions
           |> Enum.flat_map(fn d -> d["discussion"] end)
           |> Enum.frequencies_by(fn comment -> comment["discussion_id"] end) == %{"id1" => 1, "id2" => 2}
  end
end
