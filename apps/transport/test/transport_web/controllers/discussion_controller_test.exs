defmodule TransportWeb.DiscussionControllerTest do
  use TransportWeb.ConnCase, async: true
  @moduletag :capture_log
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "post_discussion" do
    test "success case", %{conn: conn} do
      %DB.Dataset{datagouv_id: datagouv_id} = dataset = insert(:dataset)
      title = "J'ai une question"
      comment = "Coucou"

      Datagouvfr.Client.Discussions.Mock
      |> expect(:post, fn %Plug.Conn{}, ^datagouv_id, ^title, ^comment ->
        {:ok, nil}
      end)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{current_user: %{"is_admin" => false}})
        |> post(
          discussion_path(conn, :post_discussion, datagouv_id, %{
            "comment" => comment,
            "title" => title,
            "dataset_slug" => dataset.slug
          })
        )

      assert redirected_to(conn, 302) == dataset_path(conn, :details, dataset.slug)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Nouvelle discussion commencée"
    end
  end

  describe "post_answer" do
    test "success case", %{conn: conn} do
      dataset = insert(:dataset)
      discussion_id = Ecto.UUID.generate()
      comment = "Coucou"

      Datagouvfr.Client.Discussions.Mock
      |> expect(:post, fn %Plug.Conn{}, ^discussion_id, ^comment, close: true ->
        {:ok, nil}
      end)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{current_user: %{"is_admin" => false}})
        |> post(
          discussion_path(conn, :post_answer, dataset.datagouv_id, discussion_id, %{
            "comment" => comment,
            "dataset_slug" => dataset.slug,
            "answer_and_close" => true
          })
        )

      assert redirected_to(conn, 302) == dataset_path(conn, :details, dataset.slug)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Réponse publiée"
    end

    test "error from the API", %{conn: conn} do
      dataset = insert(:dataset)
      discussion_id = Ecto.UUID.generate()
      comment = "Coucou"

      Datagouvfr.Client.Discussions.Mock
      |> expect(:post, fn %Plug.Conn{}, ^discussion_id, ^comment, close: false ->
        {:error, %{"message" => "The server could not verify that you are authorized to access the URL requested"}}
      end)

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(%{current_user: %{"is_admin" => false}})
        |> post(
          discussion_path(conn, :post_answer, dataset.datagouv_id, discussion_id, %{
            "comment" => comment,
            "dataset_slug" => dataset.slug
          })
        )

      assert redirected_to(conn, 302) == dataset_path(conn, :details, dataset.slug)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Impossible de publier la réponse"
    end
  end
end
