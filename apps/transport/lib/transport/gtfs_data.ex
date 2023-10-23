defmodule Transport.GTFSData do
  @moduledoc """
  A module centralizing data functions for GTFS (stops for now).

  Here is the general explanation around the algorithms used to create the national GTFS stops map,
  centralized in one place for simplicity.

  The client side (`gtfs.js`) computes the width/height in pixels and the bounding box (north/south/east/west).
  The size in pixels is useful to try to display similarly spaced clusters, as explained below.

  Server-side, `explore_controller.ex` counts the stops in the bounding box.

  Under a certain threshold, one that allows decent performance on the client side & in delay in transmission from
  the server to the client, a non-aggregate (aka "detailed") reply is generated as GeoJSON, allowing to show per-stop
  detailed information.

  Above the threshold, aggregates are returned to the client instead. The controller computes "snap x" and "snap y"
  values, which are the delta in latitude/longitude, divided per 5 pixels of screen, based on what is sent by the client.

  This is done to give the controller enough information to figure out how to display roughly equally spaced/sized "cells" on the screen,
  all while keeping the number of overall clusters for a given zoom level low enough.

  To save bandwidth and get a fast-enough experience, the aggregates are returned as [count, lat, lon] JSON arrays,
  without any key, and with reduced decimal precision.

  The aggregates are pre-computed as materialized views for each of the 12 zoom levels encountered with leaflet.
  For each zoom level, the stops are counted as aggregates via `ST_SnapToGrid`. The delta latitude/longitude for each zoom level
  has been captured from the client and hardcoded (see `@zoom_levels`).

  When an actual aggregate query needs to occur, the snap_x/snap_y computed values (thanks to what is sent by the client)
  are used to determine which zoom level is the closest in term of snap_y, which helps deciding which aggregate to pick.
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

  def build_detailed({north, south, east, west}, opts \\ []) do
    [mode: mode] = Keyword.validate!(opts, mode: :map_mode)

    stops =
      {north, south, east, west}
      |> bounding_box_points()
      |> join(:left, [gs, di], di in DB.DataImport, on: gs.data_import_id == di.id)
      |> join(:left, [gs, di, rh], rh in DB.ResourceHistory, on: di.resource_history_id == rh.id)
      |> join(:left, [gs, di, rh, r], r in DB.Resource, on: rh.resource_id == r.id)
      |> join(:left, [gs, di, rh, r, d], d in DB.Dataset, on: r.dataset_id == d.id)
      |> select([gs, di, rh, r, d], %{
        stop_id: gs.stop_id,
        stop_name: gs.stop_name,
        di_id: gs.data_import_id,
        dataset_title: d.custom_title,
        stop_lat: gs.stop_lat,
        stop_lon: gs.stop_lon,
        stop_location_type: gs.location_type
      })

      stops = if mode == :api_mode do
        stops
        |> select_merge([gs, di, rh, r, d], %{
          dataset_id: d.id,
          resource_id: r.id,
          resource_title: r.title
        })
      else
        stops
      end

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
            properties: geojson_properties(s, mode)
          }
        end)
    }
  end

  defp geojson_properties(s, :map_mode) do
    %{
      stop_id: Map.fetch!(s, :stop_id),
      stop_name: Map.fetch!(s, :stop_name),
      di_id: Map.fetch!(s, :di_id),
      dataset_title: Map.fetch!(s, :dataset_title),
      stop_location_type: Map.fetch!(s, :stop_location_type)
    }
  end

  defp geojson_properties(s, :api_mode) do
    %{
      stop_id: Map.fetch!(s, :stop_id),
      stop_name: Map.fetch!(s, :stop_name),
      di_id: Map.fetch!(s, :di_id),
      dataset_id: Map.fetch!(s, :dataset_id),
      dataset_title: Map.fetch!(s, :dataset_title),
      resource_id: Map.fetch!(s, :resource_id),
      resource_title: Map.fetch!(s, :resource_title),
      stop_location_type: Map.fetch!(s, :stop_location_type)
    }
  end


  def count_points({north, south, east, west}) do
    {north, south, east, west}
    |> bounding_box_points()
    |> DB.Repo.aggregate(:count, :id)
  end

  #
  # To recreate these values, you must compute, for each Leaflet zoom-level,
  # the following values.
  #
  # (east - west) / (width_in_pixels / 5.0)
  # (north - south) / (height_in_pixels / 5.0)
  #
  # This can be achieved for instance purely in `gtfs.js` with the following code
  # in the `moveend` event:
  #
  # ```
  #    console.log(map.getZoom())
  #    console.log((bounds.getEast() - bounds.getWest()) / (widthPixels / 5.0))
  #    console.log((bounds.getNorth() - bounds.getSouth()) / (heightPixels / 5.0))
  # ```
  #
  # The results will vary based on which screen / resolution you have, so I made
  # the computations on an average sized screen. They will also vary based on where
  # you zoom, so I worked mostly around Metropolitan France.
  #
  # Despite this limitation, they could still be used correctly for most cases.
  #
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

  def list_views(pattern) do
    query = from(v in "pg_matviews")

    query
    |> select([v], v.matviewname)
    |> where([v], like(v.matviewname, ^pattern))
    |> DB.Repo.all()
  end

  def create_if_not_exist_materialized_views do
    @zoom_levels
    |> Enum.each(fn {zoom_level, _} ->
      create_gtfs_stops_materialized_view(zoom_level)
    end)
  end

  def refresh_materialized_views do
    @zoom_levels
    |> Enum.each(fn {zoom_level, _} ->
      refresh_materialized_view(zoom_level)
    end)
  end

  @doc """
  For simplicity, this method will attempt to "create if not exist", then
  refresh the views. It means the first time ever, 2 computations will occur.
  "NO DATA" could instead be used on view creation instead if needed.
  """
  def create_or_refresh_all_materialized_views do
    create_if_not_exist_materialized_views()
    refresh_materialized_views()
  end

  def refresh_materialized_view(zoom_level) when is_integer(zoom_level) do
    # NOTE: CONCURRENTLY is better but will require a unique index first
    # Not using CONCURRENTLY means the view cannot be queried at all during the operation
    {:ok, _res} =
      Ecto.Adapters.SQL.query(DB.Repo, """
        REFRESH MATERIALIZED VIEW gtfs_stops_clusters_level_#{zoom_level}
      """)
  end

  # NOTE: the bounding box computation is done before the "create if not exists", which
  # costs a bit of time even if the view exists already.
  # NOTE: make sure to keep the integer guard to avoid SQL injections.
  def create_gtfs_stops_materialized_view(zoom_level) when is_integer(zoom_level) do
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

    # NOTE: careful with not creating a SQL injection here as in other similar places in this file.
    # Here zoom_level is not user input at time of writing.
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
      record =
        q
        |> where(
          [c],
          fragment("? between ? and ?", c.cluster_lon, ^west, ^east) and
            fragment("? between ? and ?", c.cluster_lat, ^south, ^north)
        )
        # "one" because we use jsonb_agg above, returning one record with everything
        |> DB.Repo.one()

      # if nothing is in the bounding box, return an empty array instead of nil
      if is_nil(record), do: "[]", else: record
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
