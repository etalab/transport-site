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

  @max_points 10_000

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

    count = count_points(north, south, east, west)

    data =
      if count < @max_points do
        %{
          type: "detailed",
          data: build_detailed(north, south, east, west)
        }
      else
        %{
          type: "clustered",
          data: build_clusters(north, south, east, west, snap_x, snap_y)
        }
      end

    conn |> json(data)
  end

  import Ecto.Query

  defp bounding_box_points(north, south, east, west) do
    from(gs in "gtfs_stops")
    |> where(
      [gs],
      fragment("? between ? and ?", gs.stop_lon, ^west, ^east) and
        fragment("? between ? and ?", gs.stop_lat, ^south, ^north)
    )
  end

  def build_detailed(north, south, east, west) do
    stops =
      bounding_box_points(north, south, east, west)
      |> select([gs], %{
        d_id: gs.data_import_id,
        stop_id: gs.stop_id,
        stop_name: gs.stop_name,
        stop_lat: gs.stop_lat,
        stop_lon: gs.stop_lon,
        stop_location_type: gs.location_type
      })

    %{
      type: "FeatureCollection",
      features:
        stops
        |> DB.Repo.all()
        |> Enum.map(fn s ->
          %{
            type: "Feature",
            geometry: %{
              type: "Point",
              coordinates: [Map.fetch!(s, :stop_lon), Map.fetch!(s, :stop_lat)]
            },
            properties: %{
              d_id: Map.fetch!(s, :d_id),
              stop_id: Map.fetch!(s, :stop_id),
              stop_location_type: Map.fetch!(s, :stop_location_type)
            }
          }
        end)
    }
  end

  defp count_points(north, south, east, west) do
    bounding_box_points(north, south, east, west)
    |> DB.Repo.aggregate(:count, :id)
  end

  defp build_clusters(north, south, east, west, snap_x, snap_y) do
    # NOTE: this query is not horribly slow but not super fast either. When the user
    # scrolls, this will stack up queries. It would be a good idea to cache the result for
    # some precomputed zoom levels when all the data imports are considered (no filtering).
    q = from(gs in "gtfs_stops")

    clusters =
      q
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

    q = from(e in subquery(clusters))

    q
    |> select([e], %{
      lon: selected_as(fragment("ST_X(ST_TRANSFORM(cluster, 4326))"), :cluster_lon),
      lat: selected_as(fragment("ST_Y(ST_TRANSFORM(cluster, 4326))"), :cluster_lat),
      c: selected_as(fragment("count"), :count)
    })
    |> where([e], e.count > 0)
    |> DB.Repo.all()
    |> Enum.map(fn x ->
      [
        x |> Map.fetch!(:lat) |> Decimal.from_float() |> Decimal.round(4) |> Decimal.to_float(),
        x |> Map.fetch!(:lon) |> Decimal.from_float() |> Decimal.round(4) |> Decimal.to_float(),
        x |> Map.fetch!(:c)
      ]
    end)
  end
end
