defmodule TransportWeb.Backoffice.BreakingNewsController do
  use TransportWeb, :controller

  def index(conn, _params) do
    breaking_news = DB.BreakingNews.get_breaking_news()

    conn
    |> render("index.html",
      form: Phoenix.Component.to_form(%{"msg" => breaking_news[:msg], "level" => breaking_news[:level] || :info})
    )
  end

  def update_breaking_news(conn, %{"level" => level, "msg" => msg}) do
    DB.BreakingNews.set_breaking_news(%{level: level, msg: msg})

    conn
    |> put_flash_message(msg)
    |> index(%{})
  end

  def put_flash_message(conn, "") do
    conn |> put_flash(:info, "breaking news supprimée")
  end

  def put_flash_message(conn, _msg) do
    conn |> put_flash(:info, "breaking news activée")
  end
end
