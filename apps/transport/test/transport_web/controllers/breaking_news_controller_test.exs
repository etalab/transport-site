defmodule TransportWeb.BackofficeControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: []
  import Plug.Test

  describe "breaking news home message" do
    test "no flash message by default", %{conn: conn} do
      conn =
        conn
        |> get(page_path(conn, :index))

      doc = html_response(conn, 200) |> Floki.parse_document!()
      assert [] == Floki.find(doc, ".notification")
    end

    test "security : cannot update message if not admin", %{conn: conn} do
      conn =
        conn
        |> post(backoffice_breaking_news_path(conn, :update_breaking_news, %{level: "info", msg: "coucou"}))

      assert html_response(conn, 302)
    end

    test "update a message, check it is displayed on home, delete it", %{conn: conn} do
      message = "coucou message alerte"

      # set the message
      conn_admin =
        conn
        |> init_test_session(%{
          current_user: %{"organizations" => [%{"slug" => "equipe-transport-data-gouv-fr"}]}
        })
        |> post(backoffice_breaking_news_path(conn, :update_breaking_news, %{level: "info", msg: message}))

      # message has been set with sucess
      assert html_response(conn_admin, 200)

      conn_client =
        conn
        |> get(page_path(conn, :index))

      # message is displayed on home page
      assert html_response(conn_client, 200) =~ message

      # set an empty message
      conn_admin =
        conn_admin
        |> post(backoffice_breaking_news_path(conn, :update_breaking_news, %{level: "info", msg: ""}))

      conn_client =
        conn
        |> get(page_path(conn, :index))

      # no more message is displayed on home
      doc = html_response(conn_client, 200) |> Floki.parse_document!()
      assert [] == Floki.find(doc, ".notification")
    end
  end
end
