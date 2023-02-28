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

    data = build_clusters(north, south, east, west, snap_x, snap_y)

    conn |> json(data)
  end

  import Ecto.Query

  defp build_clusters(north, south, east, west, snap_x, snap_y) do
    # NOTE: this query is not horribly slow but not super fast either. When the user
    # scrolls, this will stack up queries. It would be a good idea to cache the result for
    # some precomputed zoom levels when all the data imports are considered (no filtering).
    clusters =
      from(gs in "gtfs_stops")
      |> select([gs], %{
        cluster:
          selected_as(
            fragment("ST_SnapToGrid(ST_SetSRID(ST_MakePoint(stop_lon, stop_lat), 4326), ?, ?)", ^snap_x, ^snap_y),
            :cluster
          ),
        count: selected_as(fragment("count(*)"), :count)
      })
      |> where(
        [gs],
        fragment("? between ? and ?", gs.stop_lon, ^west, ^east) and
          fragment("? between ? and ?", gs.stop_lat, ^south, ^north)
      )
      |> group_by([gs], selected_as(:cluster))

    from(e in subquery(clusters))
    |> select([e], %{
      lon: selected_as(fragment("ST_X(ST_TRANSFORM(cluster, 4326))"), :cluster_lon),
      lat: selected_as(fragment("ST_Y(ST_TRANSFORM(cluster, 4326))"), :cluster_lat),
      c: selected_as(fragment("count"), :count)
    })
    |> where([e], e.count > 0)
    |> DB.Repo.all()
    |> Enum.map(fn x ->
      [
        Map.fetch!(x, :lat) |> Decimal.from_float() |> Decimal.round(4) |> Decimal.to_float(),
        Map.fetch!(x, :lon) |> Decimal.from_float() |> Decimal.round(4) |> Decimal.to_float(),
        Map.fetch!(x, :c)
      ]
    end)
  end
end
