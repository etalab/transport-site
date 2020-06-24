defmodule TransportWeb.Backoffice.PageController do
  use TransportWeb, :controller

  alias DB.{Dataset, LogsImport, LogsValidation, Region, Repo, Resource}
  import Ecto.Query
  require Logger

  ## Controller functions

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, %{"q" => q} = params) when q != "" do
    conn = assign(conn, :q, q)

    params
    |> Map.put("list_inactive", true)
    |> Dataset.list_datasets()
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "outdated"} = params) do
    dt = Date.utc_today() |> Date.to_iso8601()

    sub =
      Resource
      |> where([r], fragment("metadata->>'end_date' IS NOT NULL"))
      |> group_by([r], r.dataset_id)
      |> having([_q], fragment("max(metadata->>'end_date') <= ?", ^dt))
      |> distinct([r], r.dataset_id)
      |> select([r], %{dataset_id: r.dataset_id, end_date: fragment("max(metadata->>'end_date')")})

    Dataset
    |> join(:right, [d], r in subquery(sub), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "other_resources"} = params) do
    resources =
      Resource
      |> having(
        [r],
        fragment("SUM(CASE WHEN format='GTFS' or format='gbfs' or format='NeTEx' THEN 1 ELSE 0 END) > 0")
      )
      |> group_by([r], r.dataset_id)
      |> select([r], %{dataset_id: r.dataset_id, end_date: fragment("max(metadata->>'end_date')")})

    Dataset
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "not_compliant"} = params) do
    resources =
      Resource
      |> having([r], fragment("MAX(CAST(metadata->'issues_count'->>'UnloadableModel' as INT)) > 0"))
      |> group_by([r], r.dataset_id)
      |> select([r], %{dataset_id: r.dataset_id, end_date: fragment("max(metadata->>'end_date')")})

    Dataset
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id} = params) do
    conn =
      Dataset
      |> preload([:aom, :logs_import])
      |> Repo.get(dataset_id)
      |> case do
        nil ->
          put_flash(conn, :error, dgettext("backoffice", "Unable to find dataset"))

        dataset ->
          assign(conn, :dataset, dataset)
      end

    render_index(Dataset, conn, params)
  end

  def index(%Plug.Conn{} = conn, params) do
    resources =
      Resource
      |> group_by([r], r.dataset_id)
      |> select([r], %{dataset_id: r.dataset_id, end_date: fragment("max(metadata->>'end_date')")})

    Dataset
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def new(%Plug.Conn{} = conn, _) do
    conn
    |> assign(:dataset, nil)
    |> assign(:dataset_types, Dataset.types())
    |> assign(:regions, Region |> where([r], r.nom != "National") |> Repo.all())
    |> render("form_dataset.html")
  end

  def edit(%Plug.Conn{} = conn, %{"id" => dataset_id}) do
    conn =
      Dataset
      |> preload(:aom)
      |> Repo.get(dataset_id)
      |> case do
        nil -> put_flash(conn, :error, dgettext("backoffice", "Unable to find dataset"))
        dataset -> assign(conn, :dataset, dataset)
      end

    conn
    |> assign(:dataset_types, Dataset.types())
    |> assign(:regions, Region |> where([r], r.nom != "National") |> Repo.all())
    |> assign(:import_logs, LogsImport |> where([r], r.dataset_id == ^dataset_id) |> Repo.all())
    |> assign(
      :validation_logs,
      LogsValidation
      |> join(:left, [v, r], r in Resource, on: r.id == v.resource_id)
      |> where([_v, r], r.dataset_id == ^dataset_id)
      |> Repo.all()
    )
    |> render("form_dataset.html")
  end

  ## Private functions
  @spec render_index(Ecto.Queryable.t(), Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_index(datasets, conn, params) do
    config = make_pagination_config(params)

    datasets =
      datasets
      |> preload([:region, :aom, :resources])
      |> Repo.paginate(page: config.page_number)

    conn
    |> assign(:regions, Region |> where([r], r.nom != "National") |> Repo.all())
    |> assign(:datasets, datasets)
    |> assign(:dataset_types, Dataset.types())
    |> assign(:order_by, get_order_by_from_params(params))
    |> render("index.html")
  end

  @spec get_order_by_from_params(map) :: %{direction: atom, field: atom}
  defp get_order_by_from_params(params) do
    dir =
      case params do
        %{"dir" => "desc"} -> :desc
        _ -> :asc
      end

    order_by =
      case params do
        %{"order_by" => "end_date"} -> :end_date
        %{"order_by" => "spatial"} -> :spatial
        _ -> nil
      end

    %{direction: dir, field: order_by}
  end

  @spec query_order_by_from_params(any, map) :: any
  defp query_order_by_from_params(query, params) do
    %{direction: dir, field: field} = get_order_by_from_params(params)

    case field do
      :end_date -> order_by(query, [d, r], {^dir, field(r, :end_date)})
      :spatial -> order_by(query, [d, r], {^dir, field(d, :spatial)})
      _ -> query
    end
  end
end
