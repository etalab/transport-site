defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller

  def index(conn, _params) do
    conn
    |> assign(:bnlc_dataset, Transport.Jobs.BNLCToGeoData.relevant_dataset())
    |> assign(:parcs_relais_dataset, Transport.Jobs.ParkingsRelaisToGeoData.relevant_dataset())
    |> assign(:zfe_dataset, Transport.Jobs.LowEmissionZonesToGeoData.relevant_dataset())
    |> assign(:irve_dataset, Transport.Jobs.IRVEToGeoData.relevant_dataset())
    |> render("explore.html")
  end

  def vehicle_positions(conn, _params) do
    conn |> redirect(to: explore_path(conn, :index))
  end

  defp national_map_disabled?, do: Application.fetch_env!(:transport, :disable_national_gtfs_map)

  def gtfs_stops(conn, _params) do
    if national_map_disabled?() do
      conn
      |> put_status(:not_found)
      |> put_view(ErrorView)
      |> assign(:custom_message, dgettext("errors", "Feature temporarily disabled"))
      |> render("503.html")
    else
      conn
      |> assign(:page_title, dgettext("explore", "Consolidated GTFS stops map"))
      |> render("gtfs_stops.html")
    end
  end
end
