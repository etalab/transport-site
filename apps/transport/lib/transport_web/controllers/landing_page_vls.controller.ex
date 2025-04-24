defmodule TransportWeb.LandingPagesController do
  use TransportWeb, :controller

  def vls(conn, _params) do
    conn
    |> render("vls.html")
  end
end
