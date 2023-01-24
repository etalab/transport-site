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

  def gtfs_stops(conn, _params) do
    # NOTE: this will change - either I will send streamed, or streamed via newlines
    # or in blocks based on parameters, to be determined.
    data_import_ids = Transport.GTFSExportStops.data_import_ids() |> Enum.take(25)
    output = Transport.GTFSExportStops.export_stops_report(data_import_ids)

    json(conn, %{data: output})
  end
end
