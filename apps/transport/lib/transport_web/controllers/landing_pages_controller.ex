defmodule TransportWeb.LandingPagesController do
  use TransportWeb, :controller

  def vls(conn, _params) do
    conn
    |> assign(:seo_page, "vls")
    |> assign(:contact_email, Application.fetch_env!(:transport, :contact_email))
    |> render("vls.html", statistics())
  end

  defp statistics do
    Transport.Cache.fetch(
      "landing-vls-stats",
      fn -> compute_statistics() end,
      :timer.hours(12)
    )
  end

  defp compute_statistics do
    # For now it's computed by hand
    national_coverage = 70
    vehicles = 57_000

    resources = DB.Resource.count_by_format("gbfs")

    %{national_coverage: national_coverage, resources: resources, vehicles: vehicles}
  end
end
