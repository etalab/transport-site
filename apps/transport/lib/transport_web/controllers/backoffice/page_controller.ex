defmodule TransportWeb.Backoffice.PageController do
  use TransportWeb, :controller

  alias DB.{Dataset, LogsImport, Region, Repo, Resource}
  import Ecto.Query
  require Logger

  def end_dates_query() do
    DB.Dataset.base_query()
    |> DB.Dataset.join_from_dataset_to_metadata(Transport.Validators.GTFSTransport.validator_name())
    |> where([metadata: m], fragment("?->>'end_date' IS NOT NULL", m.metadata))
    |> group_by([dataset: d], d.id)
    |> select([dataset: d, metadata: m], %{dataset_id: d.id, end_date: fragment("max(?->>'end_date')", m.metadata)})
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, %{"q" => q} = params) when q != "" do
    conn = assign(conn, :q, q)

    params
    |> Map.put("list_inactive", true)
    |> Dataset.list_datasets_no_order()
    |> join(:left, [d], end_date in subquery(end_dates_query()), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "outdated"} = params) do
    dt = Date.utc_today() |> Date.to_iso8601()

    sub = end_dates_query() |> having([metadata: m], fragment("max(?->>'end_date') <= ?", m.metadata, ^dt))

    Dataset.base_query()
    |> join(:right, [d], end_date in subquery(sub), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "not_compliant"} = params) do
    sub =
      end_dates_query()
      |> having([metadata: m], fragment("MAX(CAST(?->'issues_count'->>'UnloadableModel' as INT)) > 0", m.metadata))

    Dataset.base_query()
    |> join(:inner, [d], end_date in subquery(sub), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "licence_not_specified"} = params) do
    Dataset.base_query()
    |> join(:left, [d], end_date in subquery(end_dates_query()), on: d.id == end_date.dataset_id, as: :end_dates)
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

    Dataset.base_query()
    |> join(:left, [dataset: d], end_date in subquery(end_dates_query()),
      on: d.id == end_date.dataset_id,
      as: :end_dates
    )
    |> join(:inner, [dataset: d], r in subquery(resources), on: d.id == r.dataset_id)
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

    Dataset.base_query()
    |> join(:left, [dataset: d], end_date in subquery(end_dates_query()),
      on: d.id == end_date.dataset_id,
      as: :end_dates
    )
    |> join(:inner, [dataset: d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "resource_under_90_availability"} = params) do
    datasets_id = dataset_with_resource_under_90_availability()

    Dataset.base_query()
    |> join(:left, [dataset: d], end_date in subquery(end_dates_query()),
      on: d.id == end_date.dataset_id,
      as: :end_dates
    )
    |> where([dataset: d], d.id in ^datasets_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "archived"} = params) do
    Dataset.archived()
    |> join(:left, [dataset: d], end_date in subquery(end_dates_query()),
      on: d.id == end_date.dataset_id,
      as: :end_dates
    )
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
    Dataset.base_query()
    |> join(:left, [d], end_date in subquery(end_dates_query()), on: d.id == end_date.dataset_id, as: :end_dates)
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
    |> assign(:dataset_id, dataset_id)
    |> assign(:dataset_types, Dataset.types())
    |> assign(:regions, Region |> where([r], r.nom != "National") |> Repo.all())
    |> assign(:expiration_emails, notification_expiration_emails(conn.assigns[:dataset]))
    |> assign(
      :import_logs,
      LogsImport
      |> where([v], v.dataset_id == ^dataset_id)
      |> order_by([v], desc: v.timestamp)
      |> Repo.all()
    )
    |> render("form_dataset.html")
  end

  defp notification_expiration_emails(nil), do: []

  defp notification_expiration_emails(%Dataset{} = dataset) do
    Transport.Notifications.config()
    |> Transport.Notifications.emails_for_reason(:expiration, dataset)
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

  @spec render_index(Ecto.Queryable.t(), Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_index(datasets, conn, params) do
    config = make_pagination_config(params)

    paginated_result =
      datasets
      |> preload([:region, :aom, :resources])
      |> select([dataset: d, end_dates: ed], {d, {ed.dataset_id, ed.end_date}})
      |> Repo.paginate(page: config.page_number)

    {datasets, raw_end_dates} = paginated_result.entries |> Enum.unzip()
    paginated_datasets = paginated_result |> Map.put(:entries, datasets)
    end_dates = raw_end_dates |> Enum.into(%{})

    conn
    |> assign(:regions, Region |> where([r], r.nom != "National") |> Repo.all())
    |> assign(:datasets, paginated_datasets)
    |> assign(:end_dates, end_dates)
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
        %{"order_by" => "custom_title"} -> :custom_title
        _ -> nil
      end

    %{direction: dir, field: order_by}
  end

  @spec query_order_by_from_params(any, map) :: any
  defp query_order_by_from_params(query, params) do
    %{direction: dir, field: field} = get_order_by_from_params(params)

    case field do
      :end_date -> order_by(query, [end_dates: ed], {^dir, field(ed, :end_date)})
      :custom_title -> order_by(query, [d, r], {^dir, field(d, :custom_title)})
      _ -> query
    end
  end
end
