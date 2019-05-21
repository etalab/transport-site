defmodule Datagouvfr.Client.DiscussionTest do
  use TransportWeb.ConnCase, async: false # smell
  use TransportWeb.ExternalCase # smell
  alias Datagouvfr.Client.Discussions
  alias OAuth2.AccessToken

  setup do
    conn = build_conn()
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
end
