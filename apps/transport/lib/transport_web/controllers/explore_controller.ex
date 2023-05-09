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
    conn
    |> render("gtfs_stops.html")
  end

  @max_points 20_000

  def gtfs_stops_data(conn, params) do
    %{
      "south" => south,
      "east" => east,
      "west" => west,
      "north" => north,
      "width_pixels" => width,
      "height_pixels" => height
    } = params

    {south, ""} = Float.parse(south)
    {east, ""} = Float.parse(east)
    {west, ""} = Float.parse(west)
    {north, ""} = Float.parse(north)
    {width_px, ""} = Float.parse(width)
    {height_px, ""} = Float.parse(height)

    snap_x = abs((west - east) / (width_px / 5.0))
    snap_y = abs((north - south) / (height_px / 5.0))

    count = Transport.GTFSData.count_points({north, south, east, west})

    data =
      if count < @max_points do
        %{
          type: "detailed",
          data: Transport.GTFSData.build_detailed({north, south, east, west})
        }
      else
        %{
          type: "clustered",
          # TODO: change zoom level of cached cluster dynamically
          data: Transport.GTFSData.build_clusters({north, south, east, west}, {snap_x, snap_y})
        }
      end

    conn |> json(data)
  end
end
