defmodule Datagouvfr.Client.DiscussionTest do
  use Datagouvfr.ConnCase, async: false
  use Datagouvfr.ExternalCase
  alias Datagouvfr.Client.Discussions
  alias OAuth2.AccessToken

  import Tesla.Mock

  setup do
    conn =
      build_conn()
      |> assign(:token, AccessToken.new("secret"))

    {:ok, conn: conn}
  end

  test "post discussion without extras", %{conn: conn} do
    cassette = "test/fixture/cassettes/client/discussions/post-0.json"
    [data] = File.read!(cassette) |> Jason.decode!()

    mock(fn
      %{method: :post, url: "https://demo.data.gouv.fr/api/1/discussions/"} ->
        %Tesla.Env{status: 201, body: data["response"]["body"]}
    end)

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

  test "post discussion with extras", %{conn: conn} do
    id_ = "5a6613940b5b3954c07c586a"
    title = "Test title"
    comment = "Test comment"
    extras = %{"type" => "STOP_UNUSED"}

    cassette = "test/fixture/cassettes/client/discussions/post-1.json"
    [data] = File.read!(cassette) |> Jason.decode!()

    mock(fn
      %{method: :post, url: "https://demo.data.gouv.fr/api/1/discussions/"} ->
        %Tesla.Env{status: 201, body: data["response"]["body"]}
    end)

    assert {:ok, discussion} = Discussions.post(conn, id_, title, comment, extras)
    assert Map.get(discussion, "title") == "Test title"

    assert discussion
           |> Map.get("discussion")
           |> List.first()
           |> Map.get("content") == "Test comment"

    assert Map.get(discussion, "extras") == %{"type" => "STOP_UNUSED"}
  end
end
