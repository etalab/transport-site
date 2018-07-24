defmodule TransportWeb.PageController do
  use TransportWeb, :controller

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      %{:mailchimp_newsletter_url => :transport
                                     |> Application.get_all_env()
                                     |> Keyword.get(:mailchimp_newsletter_url)}
    )
  end

  def login(conn, %{"redirect_path" => redirect_path}) do
    conn
    |> put_session(:redirect_path, redirect_path)
    |> render("login.html")
  end

  def search_organizations(conn, _params) do
    render(conn, "search_organizations.html")
  end

  def legal(conn, _params) do
    render(conn, "legal.html")
  end

  def guide(conn, _params) do
    render(conn, "guide.html")
  end
end
