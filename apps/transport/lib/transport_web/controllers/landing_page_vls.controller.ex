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

    datasets = DB.Dataset.count_by_type("bike-scooter-sharing") + DB.Dataset.count_by_type("car-motorbike-sharing")
    resources = DB.Resource.count_by_format("gbfs")

    %{datasets: datasets, resources: resources, national_coverage: national_coverage}
  end
end
