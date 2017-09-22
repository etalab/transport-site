defmodule TransportWeb.PageController do
  use TransportWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end

  def login(conn, _) do
    render conn, "login.html"
  end

  def search_organizations(conn, _) do
    render conn, "search_organizations.html"
  end

  def organization(conn, %{"slug" => slug}) do
    organization(conn, Client.organization(slug))
  end
  def organization(conn, {:ok, response}) do
    conn
    |> assign(:organization, response)
    |> assign(:is_member, is_member(response, conn))
    |> render("organization.html")
  end
  def organization(conn, {:error, _}) do
    conn
    |> render("500.html")
  end
end
