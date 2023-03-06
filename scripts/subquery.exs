import Ecto.Query

north = 46.5
south = 45.2

east = -0.9
west = -1.2

snap_x = 0.05
snap_y = 0.06

clusters =
  from(gs in "gtfs_stops")
  |> select([gs], %{
    cluster: selected_as(fragment("ST_SnapToGrid(geom, ?, ?)", ^snap_x, ^snap_y), :cluster),
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
|> IO.inspect()

count =
  from(gs in "gtfs_stops")
  |> where(
    [gs],
    fragment("? between ? and ?", gs.stop_lon, ^west, ^east) and
      fragment("? between ? and ?", gs.stop_lat, ^south, ^north)
  )
  |> DB.Repo.aggregate(:count, :id)

IO.puts("Count = #{count}")
