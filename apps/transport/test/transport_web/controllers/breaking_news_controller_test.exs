defmodule TransportWeb.BreakingNewsControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: []

  describe "breaking news home message" do
    test "no flash message by default", %{conn: conn} do
      conn = conn |> get(page_path(conn, :index))

      doc = conn |> html_response(200) |> Floki.parse_document!()
      assert [] == Floki.find(doc, ".notification")
    end

    test "security : cannot update message if not admin", %{conn: conn} do
      conn =
        conn
        |> post(backoffice_breaking_news_path(conn, :update_breaking_news, %{level: "info", msg: "coucou"}))

      assert html_response(conn, 302)
    end

    test "update a message, check it is displayed on home, delete it", %{conn: conn} do
      message = "coucou message **alerte**"
      expected_message = "coucou message <strong>alerte</strong>"

      levels = Ecto.Enum.values(DB.BreakingNews, :level)

      Enum.each(levels, fn level ->
        # set the message
        conn
        |> setup_admin_in_session()
        |> post(backoffice_breaking_news_path(conn, :update_breaking_news, %{level: level, msg: message}))
        |> html_response(200)

        response = conn |> get(page_path(conn, :index)) |> html_response(200)

        # message is displayed on home page and Markdown is rendered
        assert response =~ expected_message
      end)

      # set an empty message
      conn
      |> setup_admin_in_session()
      |> post(backoffice_breaking_news_path(conn, :update_breaking_news, %{level: hd(levels), msg: ""}))
      |> html_response(200)

      assert DB.BreakingNews |> DB.Repo.all() |> Enum.empty?()

      conn_client = conn |> get(page_path(conn, :index))

      # Message has been removed on the home page
      doc = conn_client |> html_response(200) |> Floki.parse_document!()
      refute html_response(conn_client, 200) =~ expected_message
      assert [] == Floki.find(doc, ".notification")
    end
  end
end
