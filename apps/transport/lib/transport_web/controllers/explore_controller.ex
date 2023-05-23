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

  @max_points 20_000

  def gtfs_stops_data(conn, params) do
    if national_map_disabled?() do
      conn
      |> put_status(503)
      |> json(%{error: "temporarily unavailable"})
    else
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

      if count < @max_points do
        data = %{
          type: "detailed",
          data: Transport.GTFSData.build_detailed({north, south, east, west})
        }

        conn |> json(data)
      else
        # this comes out as already-encoded JSON, hence the use of :skip_json_encoding above
        data =
          Transport.GTFSData.build_clusters_json_encoded(
            {north, south, east, west},
            {snap_x, snap_y}
          )

        conn
        |> put_resp_content_type("application/json")
        |> render("gtfs_stops_data.json",
          data: {:skip_json_encoding, Jason.encode!(%{type: "clustered", data: Jason.Fragment.new(data)})}
        )
      end
    end
  end
end
