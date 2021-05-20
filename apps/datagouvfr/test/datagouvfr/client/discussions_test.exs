defmodule Datagouvfr.Client.DiscussionTest do
  # smell
  use TransportWeb.ConnCase, async: false
  # smell
  use TransportWeb.ExternalCase
  alias Datagouvfr.Client.Discussions
  alias OAuth2.AccessToken

  setup do
    conn =
      build_conn()
      |> assign(:token, AccessToken.new("secret"))

    {:ok, conn: conn}
  end

  test "post discussion without extras", %{conn: conn} do
    use_cassette "client/discussions/post-0" do
      id_ = "5a6613940b5b3954c07c586a"
      title = "Test title"
      comment = "Test comment"
      extras = nil

      assert {:ok, discussion} = Discussions.post(conn, id_, title, comment, extras)
      assert Map.get(discussion, "title") == "Test title"
      assert Map.get(discussion, "extras") == %{}

      assert discussion
             |> Map.get("discussion")
             |> List.first()
             |> Map.get("content") == "Test comment"
    end
  end

  test "post discussion with extras", %{conn: conn} do
    use_cassette "client/discussions/post-1" do
      id_ = "5a6613940b5b3954c07c586a"
      title = "Test title"
      comment = "Test comment"
      extras = %{"type" => "STOP_UNUSED"}

      assert {:ok, discussion} = Discussions.post(conn, id_, title, comment, extras)
      assert Map.get(discussion, "title") == "Test title"

      assert discussion
             |> Map.get("discussion")
             |> List.first()
             |> Map.get("content") == "Test comment"

      assert Map.get(discussion, "extras") == %{"type" => "STOP_UNUSED"}
    end
  end

  test "get latest comment timestamp" do
    discussions = [
      %{"discussion" => [%{"posted_on" => "2020-05-12T15:07:04.547000"}]},
      %{
        "discussion" => [%{"posted_on" => "2021-05-12T15:07:00.547000"}, %{"posted_on" => "2021-05-12T15:07:04.547000"}]
      },
      %{"discussion" => [%{"posted_on" => "2021-05-12T15:06:48.512000"}]}
    ]

    assert Discussions.latest_comment_timestamp(discussions) ==
             NaiveDateTime.from_iso8601!("2021-05-12T15:07:04.547000")
  end

  test "timestamp of empty list is nil" do
    assert is_nil(Discussions.latest_comment_timestamp([]))
  end

  test "timestamp of nil is nil" do
    assert is_nil(Discussions.latest_comment_timestamp(nil))
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

    selected_discussions = Discussions.comments_posted_after(discussions, ~N[2022-01-01 00:00:00.000])

    assert selected_discussions |> Enum.frequencies_by(fn d -> d["content"] end) == %{
             "commentaire 3" => 1,
             "commentaire 4" => 1
           }

    selected_discussions_empty = Discussions.comments_posted_after(discussions, ~N[2023-01-01 00:00:00.000])
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

    assert discussions |> Discussions.comments_posted_after(nil) |> Enum.count() == 4
    assert Discussions.comments_posted_after([], nil) == []
  end

  test "comments_posted_after with empty discussions" do
    assert Discussions.comments_posted_after([], ~N[2023-01-01 00:00:00.000]) == []
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

    modified_discussions = Discussions.add_discussion_id_to_comments(discussions)

    assert modified_discussions
           |> Enum.flat_map(fn d -> d["discussion"] end)
           |> Enum.frequencies_by(fn comment -> comment["discussion_id"] end) == %{"id1" => 1, "id2" => 2}
  end
end
