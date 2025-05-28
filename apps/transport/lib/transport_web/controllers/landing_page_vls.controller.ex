defmodule TransportWeb.LandingPagesController do
  use TransportWeb, :controller

  def vls(conn, _params) do
    conn
    |> assign(:seo_page, "vls")
    |> render("vls.html")
  end
end
