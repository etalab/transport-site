defmodule TransportWeb.LandingPagesController do
  use TransportWeb, :controller

  def vls(conn, _params) do
    conn
    |> assign(:seo_page, "vls")
    |> assign(:contact_email, Application.fetch_env!(:transport, :contact_email))
    |> render("vls.html")
  end
end
