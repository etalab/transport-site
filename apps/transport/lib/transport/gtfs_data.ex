defmodule Transport.GTFSData do
  @moduledoc """
  A module centralizing data functions for GTFS (stops for now).
  """

  import Ecto.Query

  def bounding_box_points({north, south, east, west}) do
    query = from(gs in "gtfs_stops")

    query
    |> where(
      [gs],
      fragment("? between ? and ?", gs.stop_lon, ^west, ^east) and
        fragment("? between ? and ?", gs.stop_lat, ^south, ^north)
    )
  end

  def build_detailed({north, south, east, west}) do
    stops =
      {north, south, east, west}
      |> bounding_box_points()
      |> join(:left, [gs, di], di in DB.DataImport, on: gs.data_import_id == di.id)
      |> join(:left, [gs, di, rh], rh in DB.ResourceHistory, on: di.resource_history_id == rh.id)
      |> join(:left, [gs, di, rh, r], r in DB.Resource, on: rh.resource_id == r.id)
      |> join(:left, [gs, di, rh, r, d], d in DB.Dataset, on: r.dataset_id == d.id)
      |> select([gs, di, rh, r, d], %{
        d_id: gs.data_import_id,
        d_title: d.custom_title,
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
              d_title: Map.fetch!(s, :d_title),
              stop_id: Map.fetch!(s, :stop_id),
              stop_location_type: Map.fetch!(s, :stop_location_type)
            }
          }
        end)
    }
  end

  def count_points({north, south, east, west}) do
    {north, south, east, west}
    |> bounding_box_points()
    |> DB.Repo.aggregate(:count, :id)
  end

  # exploratory values, zoom level is map.getZoom()
  @zoom_levels %{
    1 => {3.5, 2.0},
    2 => {1.7578125000000004, 1.189324575526938},
    3 => {0.8789062500000002, 0.6065068377804875},
    4 => {0.4394531250000001, 0.3034851814036069},
    5 => {0.21972656250000006, 0.15165412371973086},
    6 => {0.10986328125000003, 0.07580875200863536},
    7 => {0.054931640625000014, 0.037900705683396894},
    8 => {0.027465820312500007, 0.018949562981982936},
    9 => {0.013732910156250003, 0.009474781490991468},
    10 => {0.006866455078125002, 0.004737390745495734},
    11 => {0.0034332275390624983, 0.002259008904275428},
    12 => {0.00171661376953125, 0.0011294445140095472}
  }

  def create_it_not_exist_materialized_views() do
    @zoom_levels
    |> Enum.each(fn {zoom_level, _} ->
      create_gtfs_stops_materialized_view(zoom_level)
    end)
  end

  def create_gtfs_stops_materialized_view(zoom_level)
      when is_integer(zoom_level) and zoom_level in 1..12 do
    north = DB.Repo.aggregate("gtfs_stops", :max, :stop_lat)
    south = DB.Repo.aggregate("gtfs_stops", :min, :stop_lat)
    east = DB.Repo.aggregate("gtfs_stops", :max, :stop_lon)
    west = DB.Repo.aggregate("gtfs_stops", :min, :stop_lon)

    {snap_x, snap_y} = @zoom_levels |> Map.fetch!(zoom_level)

    query = build_clusters_query({north, south, east, west}, {snap_x, snap_y})

    {sql, params} = DB.Repo.to_sql(:all, query)

    # NOTE: we cannot use parameters directly in materalized views, and will get error
    # "materialized views may not be defined using bound parameters". One solution is to
    # straight replace the $ parameters manually, something that is tolerable since the
    # parameters are all under our control at time of writing, and no SQL injection can occur.
    # potential other solutions can be found at https://dba.stackexchange.com/a/208599
    view_query = """
    CREATE MATERIALIZED VIEW IF NOT EXISTS gtfs_stops_clusters_level_#{zoom_level} AS
    #{sql}
    """

    view_query =
      view_query
      |> String.replace("$1", params |> Enum.at(0) |> Float.to_string())
      |> String.replace("$2", params |> Enum.at(1) |> Float.to_string())
      |> String.replace("$3", params |> Enum.at(2) |> Float.to_string())
      |> String.replace("$4", params |> Enum.at(3) |> Float.to_string())
      |> String.replace("$5", params |> Enum.at(4) |> Float.to_string())
      |> String.replace("$6", params |> Enum.at(5) |> Float.to_string())

    {:ok, _res} = Ecto.Adapters.SQL.query(DB.Repo, view_query)
  end

  def find_closest_zoom_level({_snap_x, snap_y}) do
    Enum.min_by(@zoom_levels, fn {_zoom_level, {_sx, sy}} ->
      abs(sy - snap_y)
    end)
  end

  import Transport.LogTimeTaken, only: [log_time_taken: 2]

  @doc """
  Build an already-encoded JSON list of arrays of lat/lon/count for all the clusters,
  leveraging the database for both the computation and the encoding (faster than with Elixir),
  and working at the closest available zoom level automatically.
  """
  def build_clusters_json_encoded({north, south, east, west}, {snap_x, snap_y}) do
    {zoom_level, {_sx, _sy}} = find_closest_zoom_level({snap_x, snap_y})

    q =
      from(gs in "gtfs_stops_clusters_level_#{zoom_level}",
        # NOTE: the rounding could be moved to the materialized view itself,
        # it would probably be faster.
        select:
          fragment(
            "jsonb_agg(jsonb_build_array(?, ?, ?))::text",
            fragment("round(cluster_lat::numeric, 4)::float"),
            fragment("round(cluster_lon::numeric, 4)::float"),
            gs.count
          )
      )

    log_time_taken("SQL query", fn ->
      q
      |> where(
        [c],
        fragment("? between ? and ?", c.cluster_lon, ^west, ^east) and
          fragment("? between ? and ?", c.cluster_lat, ^south, ^north)
      )
      # "one" because we use jsonb_agg above, returning one record with everything
      |> DB.Repo.one()
    end)
  end

  def build_clusters_query({north, south, east, west}, {snap_x, snap_y}) do
    # NOTE: this query is not horribly slow but not super fast either. When the user
    # scrolls, this will stack up queries. It would be a good idea to cache the result for
    # some precomputed zoom levels when all the data imports are considered (no filtering).
    q = from(gs in "gtfs_stops")

    clusters =
      q
      |> select([gs], %{
        cluster:
          selected_as(
            fragment(
              "ST_SnapToGrid(ST_SetSRID(ST_MakePoint(stop_lon, stop_lat), 4326), ?, ?)",
              ^snap_x,
              ^snap_y
            ),
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
  end
end
