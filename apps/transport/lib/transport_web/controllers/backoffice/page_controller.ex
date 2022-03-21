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

  def index(%Plug.Conn{} = conn, %{"filter" => "licence_not_specified"} = params) do
    Dataset
    |> where([d], d.licence == "notspecified")
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "multi_gtfs"} = params) do
    resources =
      from(r in Resource,
        where: r.format == "GTFS",
        group_by: r.dataset_id,
        select: %{dataset_id: r.dataset_id},
        having: count(r.dataset_id) > 1
      )

    Dataset
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "resource_not_available"} = params) do
    resources =
      from(r in Resource,
        where: r.is_available == false,
        group_by: r.dataset_id,
        select: %{dataset_id: r.dataset_id}
      )

    Dataset
    |> join(:inner, [d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "resource_under_90_availability"} = params) do
    datasets_id = dataset_with_resource_under_90_availability()

    Dataset
    |> where([d], d.id in ^datasets_id)
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
    |> assign(
      :import_logs,
      LogsImport
      |> where([v], v.dataset_id == ^dataset_id)
      |> order_by([v], desc: v.timestamp)
      |> Repo.all()
    )
    |> assign(
      :validation_logs,
      LogsValidation
      |> preload(:resource)
      |> join(:left, [v, r], r in Resource, on: r.id == v.resource_id)
      |> where([_v, r], r.dataset_id == ^dataset_id)
      |> order_by([v, _r], desc: v.timestamp)
      |> Repo.all()
      |> Enum.group_by(fn v -> v.resource end)
    )
    |> render("form_dataset.html")
  end

  def import_all_aoms(%Plug.Conn{} = conn, _params) do
    conn =
      try do
        Transport.ImportAOMs.run()
        conn |> put_flash(:info, "AOMs successfully imported")
      rescue
        e ->
          conn |> put_flash(:error, "AOMs import failed. #{inspect(e)}")
      end

    conn |> redirect(to: backoffice_page_path(conn, :index))
  end

  def dataset_with_resource_under_90_availability do
    query = """
    with down_ranges as (select *, tsrange(ru.start, ru.end) as down_range, tsrange(now()::timestamp - interval '30 day', now()::timestamp) as compute_range from resource_unavailability ru),
    availability as (select resource_id, r.dataset_id, 1. - (EXTRACT(EPOCH from sum(upper(down_range * compute_range) - lower(down_range * compute_range))) / EXTRACT(EPOCH from interval '30 day')) as availability from down_ranges
    left join resource r on r.id = resource_id
    group by resource_id, dataset_id)
    select distinct dataset_id from availability a
    left join dataset d on a.dataset_id = d.id
    where availability <= 0.9 and d.is_active = true
    order by dataset_id;
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(DB.Repo, query)

    List.flatten(rows)
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
