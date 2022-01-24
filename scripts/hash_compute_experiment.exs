import Ecto.Query, only: [from: 2]
import Transport.Inspect, only: [pretty_inspect: 1]

query =
  from(u in DB.Resource,
    select: map(u, [:id, :title, :content_hash, :last_import, :last_update, :url]),
    #  where: u.id == 7792 or u.id == 7793,
    order_by: :id
  )

items =
  query
  |> DB.Repo.all()

require Logger

enriched_items =
  items
  |> Task.async_stream(
    fn item ->
      Logger.info("Computing for item #{item[:id]}...")

      try do
        {:ok, status_and_hash} = HTTPStreamV2.fetch_status_and_hash(item[:url])

        item
        |> Map.put(:content_hash_v2, status_and_hash[:hash])

        #        |> Map.put(:content_hash_v1, Hasher.compute_sha256(item[:url]))
      rescue
        _ -> item
      end
    end,
    max_concurrency: 50,
    timeout: 180_000
  )
  |> Enum.to_list()
  |> Enum.map(fn {:ok, data} -> data end)
  |> Enum.map(fn x ->
    cmp = if x[:content_hash_v1] == x[:content_hash_v2], do: "OK", else: "KO"
    Map.put(x, :check, cmp)
  end)

pretty_inspect(enriched_items)

# File.write!("intermediate.json", Jason.encode!(enriched_items, pretty: true))
