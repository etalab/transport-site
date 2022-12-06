defmodule TransportWeb.Backoffice.BrokenUrlsController do
  use TransportWeb, :controller
  import Ecto.Query

  def index(conn, _params) do
    conn
    |> render("index.html", broken_urls: broken_urls())
  end

  def broken_urls do
    urls_query =
      DB.DatasetHistory
      |> join(:left, [dh], dhr in DB.DatasetHistoryResources, on: dh.id == dhr.dataset_history_id)
      |> group_by([dh], [dh.dataset_id, dh.inserted_at])
      |> order_by([dh], asc: dh.dataset_id, desc: dh.inserted_at)
      |> select([dh, dhr], %{
        dataset_id: dh.dataset_id,
        inserted_at: dh.inserted_at,
        urls: fragment("array_agg(?.payload->>'download_url')", dhr)
      })

    q = from(urls in subquery(urls_query))

    previous_urls_query =
      q
      |> windows([urls], w: [partition_by: urls.dataset_id, order_by: urls.inserted_at])
      |> select([urls], %{
        dataset_id: urls.dataset_id,
        inserted_at: urls.inserted_at,
        urls: urls.urls,
        previous_urls: urls.urls |> lag() |> over(:w)
      })

    q = from(urls in subquery(previous_urls_query))

    broken_urls =
      q
      |> distinct([urls], urls.dataset_id)
      |> select([urls], %{
        dataset_id: urls.dataset_id,
        inserted_at: urls.inserted_at,
        urls: urls.urls,
        previous_urls: urls.previous_urls,
        disappeared_urls: fragment("not urls @> previous_urls"),
        new_urls: fragment("not previous_urls @> urls")
      })
      |> order_by([urls], desc: urls.inserted_at, asc: urls.dataset_id)
      |> where([urls], fragment("not urls @> previous_urls") and fragment("not previous_urls @> urls"))

    q = from(urls in subquery(broken_urls))

    q
    |> order_by([urls], desc: urls.inserted_at)
    |> select([urls], urls)
    |> DB.Repo.all()
  end
end
