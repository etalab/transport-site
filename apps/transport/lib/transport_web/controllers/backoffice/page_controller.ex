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
    dt = Date.utc_today() |> Date.to_iso8601()

    sub = Resource
    |> group_by([r], r.dataset_id)
    |> having([_q], fragment("max(metadata->>'end_date') <= ?", ^dt))
    |> distinct([r], r.dataset_id)
    |> select([r], %Resource{dataset_id: r.dataset_id})

    Dataset
    |> join(:left, [d], r in subquery(sub), on: d.id == r.dataset_id)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "other_resources"} = params) do
    resources =
      Resource
      |> where([r], r.format != "GTFS" and r.format != "gbfs" and r.format != "netex")
      |> distinct([r], r.dataset_id)
      |> select([r], %Resource{dataset_id: r.dataset_id})

    Dataset
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id} = params) do
    conn = Dataset
    |> preload(:aom)
    |> Repo.get(dataset_id)
    |> case do
      nil -> put_flash(conn, :error, dgettext("backoffice", "Unable to find dataset"))
      dataset -> assign(conn, :dataset, dataset)
    end

    render_index(Dataset, conn, params)
  end

  def index(%Plug.Conn{} = conn, params), do: render_index(Dataset, conn, params)

  ## Private functions
  defp render_index(datasets, conn, params) do
    config = make_pagination_config(params)

    datasets = datasets
    |> preload([:region, :aom, :resources])
    |> Repo.paginate(page: config.page_number)

    conn
    |> assign(:regions, Repo.all(Region))
    |> assign(:datasets, datasets)
    |> assign(:dataset_types, Dataset.types())
    |> render("index.html")
  end
end
