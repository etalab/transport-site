# exploratory script to compute start date & end date of the latest resource history
# of each available GTFS resource, & dump them as a CSV file.

import Ecto.Query

content =
  DB.Resource.base_query()
  |> where(format: "GTFS")
  |> join(:left, [resource: r], rh in DB.ResourceHistory,
    on: rh.resource_id == r.id,
    as: :resource_history
  )
  |> join(:left, [resource_history: rh], mv in DB.MultiValidation,
    on: mv.resource_history_id == rh.id,
    as: :mv
  )
  |> distinct([resource: r], r.id)
  |> order_by([resource: r, resource_history: rh],
    asc: r.id,
    desc: rh.inserted_at
  )
  |> join(:left, [mv: mv], rm in DB.ResourceMetadata, on: rm.multi_validation_id == mv.id, as: :rm)
  # |> limit(1)
  |> select([resource: r, rm: rm], %{
    resource_id: r.id,
    inserted_at: fragment("?::date::text", rm.inserted_at),
    start_date: fragment("?->>'start_date'", rm.metadata),
    end_date: fragment("?->>'end_date'", rm.metadata)
  })
  |> DB.Repo.all()
  |> Enum.map(fn x -> x[:end_date] end)
  |> Enum.join("\n")

File.write!("gtfs-expiry-dates.csv", content)
