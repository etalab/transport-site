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

  def shortlist(conn, _) do
      render conn, "shortlist.html"
  end

end
