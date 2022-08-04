defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller

  def index(conn, _params) do
    conn
    |> render("explore.html")
  end

  def vehicle_positions(conn, _params) do
    conn
    |> redirect(to: explore_path(conn, :index))
  end

  def siri(conn, _params) do
    conn
    |> render("siri.html")
  end
end
