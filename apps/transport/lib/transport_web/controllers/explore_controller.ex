defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller

  def index(conn, _params) do
    conn
    |> assign(:bnlc_dataset, Transport.Jobs.BNLCToGeoData.relevant_dataset())
    |> assign(:parcs_relais_dataset, Transport.Jobs.ParkingsRelaisToGeoData.relevant_dataset())
    |> assign(:zfe_dataset, Transport.Jobs.LowEmissionZonesToGeoData.relevant_dataset())
    |> render("explore.html")
  end

  def vehicle_positions(conn, _params) do
    conn |> redirect(to: explore_path(conn, :index))
  end
end
