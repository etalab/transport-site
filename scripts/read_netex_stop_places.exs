file = "cache-dir/resource-81470.dat"

resource = DB.Repo.get_by!(DB.Resource, id: 81470)

coordinates =
  Transport.NeTEx.read_all_stop_places(file)
  |> Enum.flat_map(fn {_file, stops} -> stops end)
  |> Enum.map(fn %{latitude: lat, longitude: lon} -> {lon, lat} end)

search_points = %Geo.MultiPoint{coordinates: coordinates, srid: 4326}

resource
|> DB.Resource.changeset(%{search_points: search_points})
|> DB.Repo.update!()

import Ecto.Query

query =
  from(r in DB.Resource,
    select: fragment("ST_AsGeoJSON(?)", r.search_points),
    where: r.id == 81470
  )

DB.Repo.one!(query)
|> IO.puts()

# Which AOMs intersect at least one point with the search points,
# and how many points are included? Can be helpful for a variety of things,
# including a "detail search page for an AOM" (suggest everything that goes
# through the territory)
dumped_points_query =
  from(r in DB.Resource,
    where: r.id == 81470,
    select: %{id: r.id, point: fragment("(ST_Dump(?)).geom", r.search_points)}
  )

query =
  from(a in DB.AOM,
    join: r in subquery(dumped_points_query),
    on: fragment("ST_Intersects(?, ?)", r.point, a.geom),
    group_by: [r.id, a.id, a.nom, a.forme_juridique],
    order_by: [desc: count(r.point)],
    select: %{
      r_id: r.id,
      aom_id: a.id,
      nom: a.nom,
      forme_juridique: a.forme_juridique,
      num_points: count(r.point)
    }
  )

# Execute the query
DB.Repo.all(query)
|> IO.inspect()
