defmodule TransportWeb.Backoffice.BreakingNewsController do
  use TransportWeb, :controller

  def index(conn, _params) do
    conn
    |> render("index.html", current_breaking_news: DB.BreakingNews.get_breaking_news())
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
