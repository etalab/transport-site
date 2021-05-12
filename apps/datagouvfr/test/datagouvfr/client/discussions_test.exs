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
end
