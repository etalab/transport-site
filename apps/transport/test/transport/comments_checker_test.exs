defmodule Transport.CommentsCheckerTest do
  use ExUnit.Case, async: false
  alias Transport.CommentsChecker
  alias DB.{Dataset, Repo}
  import DB.Factory
  import Mock
  import Mox
  setup :verify_on_exit!


  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def assert_dataset_ts(id, timestamp) do
    %{latest_data_gouv_comment_timestamp: db_ts} = Dataset |> Repo.get!(id)

    case timestamp do
      nil ->
        assert is_nil(db_ts)

      timestamp ->
        timestamp = NaiveDateTime.from_iso8601!(timestamp)
        assert NaiveDateTime.diff(timestamp, db_ts) < 1
    end
  end

  test "check for new comments on data.gouv.fr" do
    %{id: dataset_id} = insert(:dataset, datagouv_title: "dataset 1")

    # when the dataset is created, no comment timestamp is stored
    assert_dataset_ts(dataset_id, nil)

    get_mock = fn _url, [], _ ->
      {:ok,
       %{
         "data" => [
           %{
             "id" => "discussion_id_1",
             "discussion" => [
               %{"posted_on" => "2020-01-01T12:00:00.000100", "content" => "commentaire 1"}
             ]
           }
         ]
       }}
    end

    with_mock Datagouvfr.Client.API, get: get_mock do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 1, fn _, _, _, _, _, _, _ -> {:ok, "envoyé !"} end)

      number_new_comments = CommentsChecker.check_for_new_comments()

      assert number_new_comments == 1
      verify!(Transport.EmailSender.Mock)
      assert_dataset_ts(dataset_id, "2020-01-01T12:00:00.000100")
    end

    # second run : we shouldn't find new comment
    with_mock Datagouvfr.Client.API, get: get_mock do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 0, fn _, _, _, _, _, _, _ -> {:ok, "envoyé !"} end)

      number_new_comments = CommentsChecker.check_for_new_comments()

      assert number_new_comments == 0
      verify!(Transport.EmailSender.Mock)
      assert_dataset_ts(dataset_id, "2020-01-01T12:00:00.000100")
    end

    # we add a new comment
    get_mock = fn _url, [], _ ->
      {:ok,
       %{
         "data" => [
           %{
             "id" => "discussion_id_1",
             "discussion" => [
               %{"posted_on" => "2020-01-01T12:00:00.000100", "content" => "commentaire 1"},
               %{"posted_on" => "2021-01-01T12:00:00.000200", "content" => "commentaire 2"}
             ]
           }
         ]
       }}
    end

    with_mock Datagouvfr.Client.API, get: get_mock do
      Transport.EmailSender.Mock
      |> expect(:send_mail, 1, fn _, _, _, _, _, _, _ -> {:ok, "envoyé !"} end)

      number_new_comments = CommentsChecker.check_for_new_comments()

      assert number_new_comments == 1
      verify!(Transport.EmailSender.Mock)
      assert_dataset_ts(dataset_id, "2021-01-01T12:00:00.000200")
    end
  end

  test "get latest comment timestamp" do
    discussions = [
      %{"posted_on" => "2020-05-12T15:07:04.547000"},
      %{"posted_on" => "2021-05-12T15:07:00.547000"},
      %{"posted_on" => "2021-05-12T15:07:04.547000"},
      %{"posted_on" => "2021-05-12T15:06:48.512000"}
    ]

    assert CommentsChecker.comments_latest_timestamp(discussions) ==
             NaiveDateTime.from_iso8601!("2021-05-12T15:07:04.547000")
  end

  test "timestamp of empty list is nil" do
    assert is_nil(CommentsChecker.comments_latest_timestamp([]))
  end

  test "timestamp of nil is nil" do
    assert is_nil(CommentsChecker.comments_latest_timestamp(nil))
  end

  test "fetch comments for datasets posted after timestamp" do
    discussions = [
      %{"discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000", "content" => "commentaire 1"}]},
      %{
        "discussion" => [
          %{"posted_on" => "2020-05-12T15:07:00.547000", "content" => "commentaire 2"},
          %{"posted_on" => "2022-05-12T15:07:04.547000", "content" => "commentaire 3"}
        ]
      },
      %{"discussion" => [%{"posted_on" => "2022-05-12T15:06:48.512000", "content" => "commentaire 4"}]}
    ]

    selected_discussions = CommentsChecker.comments_posted_after(discussions, ~N[2022-01-01 00:00:00.000])

    assert selected_discussions |> Enum.frequencies_by(fn d -> d["content"] end) == %{
             "commentaire 3" => 1,
             "commentaire 4" => 1
           }

    selected_discussions_empty = CommentsChecker.comments_posted_after(discussions, ~N[2023-01-01 00:00:00.000])
    assert selected_discussions_empty == []
  end

  test "comments_posted_after with nil timestamp" do
    discussions = [
      %{"discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000", "content" => "commentaire 1"}]},
      %{
        "discussion" => [
          %{"posted_on" => "2020-05-12T15:07:00.547000", "content" => "commentaire 2"},
          %{"posted_on" => "2022-05-12T15:07:04.547000", "content" => "commentaire 3"}
        ]
      },
      %{"discussion" => [%{"posted_on" => "2022-05-12T15:06:48.512000", "content" => "commentaire 4"}]}
    ]

    assert discussions |> CommentsChecker.comments_posted_after(nil) |> Enum.count() == 4
    assert CommentsChecker.comments_posted_after([], nil) == []
  end

  test "comments_posted_after with empty discussions" do
    assert CommentsChecker.comments_posted_after([], ~N[2023-01-01 00:00:00.000]) == []
  end

  test "add a discussion id to comments" do
    discussions = [
      %{"id" => "id1", "discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000", "content" => "commentaire 1"}]},
      %{
        "id" => "id2",
        "discussion" => [
          %{"posted_on" => "2020-05-12T15:07:00.547000", "content" => "commentaire 2"},
          %{"posted_on" => "2022-05-12T15:07:04.547000", "content" => "commentaire 3"}
        ]
      }
    ]

    modified_discussions = CommentsChecker.add_discussion_id_to_comments(discussions)

    assert modified_discussions
           |> Enum.flat_map(fn d -> d["discussion"] end)
           |> Enum.frequencies_by(fn comment -> comment["discussion_id"] end) == %{"id1" => 1, "id2" => 2}
  end
end
