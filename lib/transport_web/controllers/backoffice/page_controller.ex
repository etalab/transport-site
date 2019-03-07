defmodule TransportWeb.Backoffice.PageController do
  use TransportWeb, :controller

  alias Transport.{Dataset, Region, Repo, Resource}
  import Ecto.Query
  require Logger

  ## Controller functions

  def index(%Plug.Conn{} = conn, %{"q" => q} = params) when q != "" do
    conn = assign(conn, :q, q)

    q
    |> Dataset.search_datasets
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "outdated"} = params) do
    dt = DateTime.utc_now() |> DateTime.to_string()
    sub = Resource
    |> where([_q], fragment("metadata->>'end_date' <= ?", ^dt))

    Dataset
    |> join(:inner, [d], r in subquery(sub), on: d.id == r.dataset_id)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, params), do: render_index(Dataset, conn, params)

  ## Private functions
  defp region_names do
    Region
    |> Repo.all()
    |> Enum.map(fn r -> {r.nom, r.id} end)
    |> Enum.concat([{"Pas de region", nil}])
  end

  defp render_index(datasets, conn, params) do
    config = make_pagination_config(params)

    datasets = datasets
    |> preload([:region, :aom, :resources])
    |> Repo.paginate(page: config.page_number)

    conn
    |> assign(:regions, region_names())
    |> assign(:datasets, datasets)
    |> assign(:dataset_types, Dataset.dataset_types())
    |> render("index.html")
  end
end
