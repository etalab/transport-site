defmodule Datagouvfr.Client.DiscussionTest do
  use Datagouvfr.ConnCase, async: true
  alias Datagouvfr.Client.Discussions
  import Tesla.Mock

  @token_secret Ecto.UUID.generate()

  setup do
    {:ok, conn: build_conn() |> assign(:token, OAuth2.AccessToken.new(@token_secret))}
  end

  test "start a new discussion", %{conn: conn} do
    datagouv_id = Ecto.UUID.generate()
    title = "Test title"
    comment = "Test comment"

    mock(fn %Tesla.Env{method: :post, url: "https://demo.data.gouv.fr/api/1/discussions/", body: body, headers: headers} ->
      assert headers == [
               {"accept", "application/json"},
               {"authorization", "Bearer #{@token_secret}"},
               {"content-type", "application/json"}
             ]

      assert Jason.decode!(body) == Jason.decode!(~s({"comment":"#{comment}","subject":{"class":"Dataset","id":"#{datagouv_id}"},"title":"#{title}"}))
      json(%{"title" => title, "discussion" => [%{"content" => comment}]}, status: 201)
    end)

    assert {:ok, discussion} = Discussions.post(conn, datagouv_id, title, comment)
    assert Map.get(discussion, "title") == title

    assert discussion
           |> Map.get("discussion")
           |> List.first()
           |> Map.get("content") == comment
  end

  test "post a comment on a discussion", %{conn: conn} do
    comment = "Test comment"
    api_url = "https://demo.data.gouv.fr/api/1/discussions/#{datagouv_id = Ecto.UUID.generate()}/"

    mock(fn %Tesla.Env{method: :post, url: ^api_url, body: body, headers: headers} ->
      assert headers == [
               {"accept", "application/json"},
               {"authorization", "Bearer #{@token_secret}"},
               {"content-type", "application/json"}
             ]

      assert body == ~s({"close":false,"comment":"#{comment}"})
      json(%{"discussion" => [%{"content" => comment}]})
    end)

    assert {:ok, discussion} = Discussions.post(conn, datagouv_id, comment)

    assert discussion
           |> Map.get("discussion")
           |> List.first()
           |> Map.get("content") == comment
  end

  test "post a comment and close a discussion", %{conn: conn} do
    comment = "Test comment"
    api_url = "https://demo.data.gouv.fr/api/1/discussions/#{datagouv_id = Ecto.UUID.generate()}/"

    mock(fn %Tesla.Env{method: :post, url: ^api_url, body: body, headers: headers} ->
      assert headers == [
               {"accept", "application/json"},
               {"authorization", "Bearer #{@token_secret}"},
               {"content-type", "application/json"}
             ]

      assert body == ~s({"close":true,"comment":"#{comment}"})
      json(%{"discussion" => [%{"content" => comment}]})
    end)

    assert {:ok, _} = Discussions.post(conn, datagouv_id, comment, close: true)
  end
end
