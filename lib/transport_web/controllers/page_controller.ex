defmodule TransportWeb.PageController do
  use TransportWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def login(conn, %{"redirect_path" => redirect_path}) do
    conn
    |> put_session(:redirect_path, redirect_path)
    |> render("login.html")
  end

  def search_organizations(conn, _params) do
    render(conn, "search_organizations.html")
  end
end
