defmodule TransportWeb.ExploreController do
  use TransportWeb, :controller
  import Ecto.Query

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
    conn =
      conn
      |> put_resp_content_type("application/json")
      |> send_chunked(:ok)

    # NOTE: at this point the client-side seems to digest the whole JSON easily, chunked,
    # so that will do for now, unless I need more splitting.
    chunk(conn, "[")

    Transport.GTFSExportStops.data_import_ids()
    |> Enum.chunk_every(25)
    |> Enum.each(fn ids ->
      stops =
        DB.GTFS.Stops
        |> where([s], s.data_import_id in ^ids)
        |> order_by([s], [s.data_import_id, s.id])
        |> select([s], %{
          d_id: s.data_import_id,
          stop_id: s.stop_id,
          stop_name: s.stop_name,
          stop_lat: s.stop_lat,
          stop_lon: s.stop_lon,
          stop_location_type: s.location_type
        })
        |> DB.Repo.all()
        # TODO: make order deterministic
        |> Enum.map(fn x -> Map.values(x) end)

      chunk(conn, Jason.encode!(stops) <> ",")
    end)

    chunk(conn, "[]]")
    conn
  end
end
