defmodule Transport.GTFSData do
  @moduledoc """
  A module centralizing data functions for GTFS (stops for now).
  """

  import Ecto.Query

  def bounding_box_points(north, south, east, west) do
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

  def count_points(north, south, east, west) do
    bounding_box_points(north, south, east, west)
    |> DB.Repo.aggregate(:count, :id)
  end

  def build_clusters(north, south, east, west, snap_x, snap_y) do
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
