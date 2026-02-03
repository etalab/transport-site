defmodule TransportWeb.Backoffice.PageController do
  use TransportWeb, :controller

  alias DB.{Dataset, LogsImport, Region, Repo, Resource}
  import Ecto.Query
  require Logger

  def end_dates_query do
    DB.Dataset.base_with_hidden_datasets()
    |> DB.Dataset.join_from_dataset_to_metadata(
      Enum.map(Transport.ValidatorsSelection.validators_for_feature(:backoffice_page_controller), & &1.validator_name())
    )
    |> where([metadata: m], fragment("?->>'end_date' IS NOT NULL", m.metadata))
    |> group_by([dataset: d], d.id)
    |> select([dataset: d, metadata: m], %{dataset_id: d.id, end_date: fragment("max(?->>'end_date')", m.metadata)})
  end

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, %{"q" => q} = params) when q != "" do
    conn = assign(conn, :q, q)

    params
    |> Dataset.list_datasets_no_order()
    |> DB.Dataset.include_hidden_datasets()
    |> join(:left, [d], end_date in subquery(end_dates_query()), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "outdated"} = params) do
    dt = Date.utc_today() |> Date.to_iso8601()

    sub = end_dates_query() |> having([metadata: m], fragment("max(?->>'end_date') <= ?", m.metadata, ^dt))

    DB.Dataset.base_with_hidden_datasets()
    |> join(:right, [d], end_date in subquery(sub), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "not_compliant"} = params) do
    sub =
      end_dates_query()
      |> having([metadata: m], fragment("MAX(CAST(?->'issues_count'->>'UnloadableModel' as INT)) > 0", m.metadata))

    DB.Dataset.base_with_hidden_datasets()
    |> join(:inner, [d], end_date in subquery(sub), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "licence_not_specified"} = params) do
    DB.Dataset.base_with_hidden_datasets()
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

    DB.Dataset.base_with_hidden_datasets()
    |> join_left_with_end_dates()
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

    DB.Dataset.base_with_hidden_datasets()
    |> join_left_with_end_dates()
    |> join(:inner, [dataset: d], r in subquery(resources), on: d.id == r.dataset_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "resource_under_90_availability"} = params) do
    datasets_id = dataset_with_resource_under_90_availability()

    DB.Dataset.base_with_hidden_datasets()
    |> join_left_with_end_dates()
    |> where([dataset: d], d.id in ^datasets_id)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "archived"} = params) do
    Dataset.archived()
    |> join_left_with_end_dates()
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "hidden"} = params) do
    DB.Dataset.hidden()
    |> join_left_with_end_dates()
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, %{"filter" => "inactive"} = params) do
    Dataset.inactive()
    |> join_left_with_end_dates()
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  def index(%Plug.Conn{} = conn, params) do
    DB.Dataset.base_with_hidden_datasets()
    |> join(:left, [d], end_date in subquery(end_dates_query()), on: d.id == end_date.dataset_id, as: :end_dates)
    |> query_order_by_from_params(params)
    |> render_index(conn, params)
  end

  defp get_regions_for_select do
    Region |> where([r], r.nom != "National") |> select([r], {r.nom, r.id}) |> Repo.all()
  end

  def new(%Plug.Conn{} = conn, _) do
    conn
    |> assign(:dataset, nil)
    |> assign(:dataset_types, Dataset.types())
    |> assign(:regions, get_regions_for_select())
    |> render("form_dataset.html")
  end

  def edit(%Plug.Conn{} = conn, %{"id" => dataset_id}) do
    conn =
      load_dataset(dataset_id)
      |> case do
        nil -> put_flash(conn, :error, dgettext("backoffice", "Unable to find dataset"))
        dataset -> assign(conn, :dataset, dataset)
      end

    reuser_subscriptions =
      conn.assigns[:dataset].notification_subscriptions
      |> Enum.filter(fn sub -> sub.role == :reuser end)

    reusers_count =
      reuser_subscriptions
      |> Enum.uniq_by(& &1.contact)
      |> Enum.count()

    conn
    |> assign(:dataset_id, dataset_id)
    |> assign(:dataset_types, Dataset.types())
    |> assign(:regions, get_regions_for_select())
    |> assign(:notifications_sent, notifications_sent(conn.assigns[:dataset]))
    |> assign(:notifications_last_nb_days, notifications_last_nb_days())
    |> assign(:resources_with_history, DB.Dataset.last_resource_history(dataset_id))
    |> assign(:contacts_datalist, contacts_datalist())
    |> assign(:contacts_in_org, contacts_in_org(conn.assigns[:dataset]))
    |> assign(:subscriptions_by_producer, subscriptions_by_producer(conn.assigns[:dataset]))
    |> assign(:reusers_count, reusers_count)
    |> assign(:reuser_subscriptions_count, reuser_subscriptions |> Enum.count())
    |> assign(:resource_formats, resource_formats())
    |> assign(
      :import_logs,
      LogsImport
      |> where([v], v.dataset_id == ^dataset_id)
      |> order_by([v], desc: v.timestamp)
      |> Repo.all()
    )
    |> render("form_dataset.html")
  end

  def load_dataset(dataset_id) do
    DB.Dataset
    |> preload([
      :notification_subscriptions,
      [notification_subscriptions: :contact],
      [organization_object: :contacts],
      :legal_owners_aom,
      :legal_owners_region,
      :declarative_spatial_areas,
      :offers,
      :dataset_subtypes,
      :resources
    ])
    |> Repo.get(dataset_id)
  end

  defp resource_formats do
    DB.Resource.base_query()
    |> select([r], r.format)
    |> group_by([r], r.format)
    |> order_by([r], {:desc, count(r.format)})
    |> DB.Repo.all()
  end

  def subscriptions_by_producer(%DB.Dataset{} = dataset) do
    dataset.notification_subscriptions
    |> Enum.filter(fn sub -> sub.role == :producer end)
    |> Enum.sort_by(&{&1.contact.last_name, &1.reason})
    |> Enum.group_by(& &1.contact)
    |> Map.to_list()
    |> Enum.sort_by(fn {contact, _} -> contact.last_name end)
  end

  def contacts_in_org(%DB.Dataset{organization_object: %DB.Organization{} = organization_object}) do
    Enum.sort_by(organization_object.contacts, &DB.Contact.display_name/1)
  end

  def contacts_in_org(_), do: []

  defp contacts_datalist do
    DB.Contact.base_query()
    |> select([contact: c], [:first_name, :last_name, :mailing_list_title, :organization, :id])
    |> DB.Repo.all()
  end

  defp notifications_last_nb_days, do: 30

  def notifications_sent(nil), do: []

  def notifications_sent(%Dataset{id: dataset_id}) do
    datetime_limit = DateTime.utc_now() |> DateTime.add(-notifications_last_nb_days(), :day)

    DB.Notification
    |> where([n], n.dataset_id == ^dataset_id and n.inserted_at >= ^datetime_limit)
    |> select([n], [:email, :reason, :inserted_at])
    |> DB.Repo.all()
    |> Enum.group_by(
      fn %DB.Notification{reason: reason, inserted_at: inserted_at} ->
        {reason, %{DateTime.truncate(inserted_at, :second) | second: 0}}
      end,
      fn %DB.Notification{email: email} -> email end
    )
    |> Enum.sort_by(fn {{_reason, %DateTime{} = dt}, _emails} -> dt end, {:desc, DateTime})
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
      |> preload([:resources])
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
        %{"order_by" => param} when param in ["end_date", "custom_title", "organization"] ->
          String.to_existing_atom(param)

        _ ->
          nil
      end

    %{direction: dir, field: order_by}
  end

  defp join_left_with_end_dates(%Ecto.Query{} = query) do
    join(query, :left, [dataset: d], end_date in subquery(end_dates_query()),
      on: d.id == end_date.dataset_id,
      as: :end_dates
    )
  end

  @spec query_order_by_from_params(any, map) :: any
  defp query_order_by_from_params(query, params) do
    %{direction: dir, field: field} = get_order_by_from_params(params)

    case field do
      :end_date -> order_by(query, [end_dates: ed], {^dir, field(ed, :end_date)})
      :custom_title -> order_by(query, [d, r], {^dir, field(d, :custom_title)})
      :organization -> order_by(query, [d, r], {^dir, field(d, :organization)})
      _ -> query
    end
  end

  def clear_proxy_config(%Plug.Conn{} = conn, _) do
    Application.fetch_env!(:transport, :unlock_config_fetcher).clear_config_cache!()

    conn |> text("OK")
  end

  def download_resources_csv(%Plug.Conn{} = conn, _) do
    %Postgrex.Result{columns: columns, rows: rows} = resources_query()
    filename = "ressources-#{Date.utc_today() |> Date.to_iso8601()}.csv"

    content =
      rows
      |> Enum.map(fn row -> columns |> Enum.zip(row) |> Enum.into(%{}) end)
      |> CSV.encode(headers: columns)
      |> Enum.to_list()
      |> to_string()

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, content)
  end

  defp resources_query do
    DB.Repo
    |> Ecto.Adapters.SQL.query!("""
    select
      d.organization nom_organisation,
      d.datagouv_title dataset_titre_datagouv,
      d.custom_title dataset_titre_pan,
      'https://transport.data.gouv.fr/datasets/' || d.slug dataset_url,
      d.licence licence,
      d.type dataset_type,
      ds.dataset_sub_types,
      case when d.custom_tags is null or cardinality(d.custom_tags) = 0 then null else d.custom_tags end dataset_custom_tags,
      d.organization_type type_publicateur,
      re.nom nom_region,
      o.offre_mobilite,
      administrative_division.noms couverture_spatiale,
      coalesce(legal_owners.noms, d.legal_owner_company_siren::varchar) representants_legaux,
      case when d.is_active and d.archived_at is null then 'actif' when not d.is_active then 'supprimé' when d.archived_at is not null then 'archivé' end statut_datagouv,
      r.title titre_ressource,
      r.url url_ressource,
      r.type type_ressource,
      r.is_community_resource est_ressource_communautaire,
      r.format format_ressource,
      r.format in ('gtfs-rt', 'gbfs', 'SIRI', 'SIRI Lite') est_temps_reel_ressource,
      case when r.url like 'https://static.data.gouv.fr%' then 'manuelle' else 'automatique' end methode_maj,
      rh.inserted_at derniere_maj,
      case when mv.validator = 'GTFS transport-validator' then mv.max_error else mv.result->>'errors_count' end validation_errors,
      rm.metadata->>'end_date' gtfs_date_fin,
      d.organization_id id_organisation,
      d.id id_dataset,
      r.id id_ressource,
      freshness_score.score score_fraicheur,
      availability_score.score score_disponibilite,
      compliance_score.score score_conformite
    from resource r
    join dataset d on d.id = r.dataset_id
    left join dataset_geographic_view dgv on dgv.dataset_id = d.id
    left join region re on re.id = dgv.region_id
    left join (
      select
        d.id dataset_id,
        string_agg(o.nom_commercial, ',' order by o.nom_commercial) offre_mobilite
      from dataset d
      left join dataset_offer dao on dao.dataset_id = d.id
      left join offer o on o.id = dao.offer_id
      group by 1
    ) o on o.dataset_id = d.id
    left join (
      select
        rh.*,
        row_number() over (partition by rh.resource_id order by rh.inserted_at desc) row_number
      from resource_history rh
    ) rh on rh.resource_id = r.id and rh.row_number = 1
    left join (
      select
        dataset_id,
        string_agg(nom, ',' order by nom) noms
      from (
        select dr.dataset_id, r.nom nom
        from dataset_region_legal_owner dr
        join region r on dr.region_id = r.id

        union

        select da.dataset_id, a.nom
        from dataset_aom_legal_owner da
        join aom a on da.aom_id = a.id
      ) t
      group by dataset_id
    ) legal_owners on legal_owners.dataset_id = d.id
    left join (
       select
        ddsa.dataset_id,
        string_agg(ad.nom, ',' order by ad.nom) noms
      from dataset_declarative_spatial_area ddsa
      join administrative_division ad on ad.id = ddsa.administrative_division_id
      group by ddsa.dataset_id
    ) administrative_division on administrative_division.dataset_id = d.id
    left join multi_validation mv on mv.resource_history_id = rh.id
    left join resource_metadata rm on rm.multi_validation_id = mv.id
    left join (
      select
        d.id dataset_id,
        string_agg(ds.slug, ',' order by ds.slug) dataset_sub_types
      from dataset d
      left join dataset_dataset_subtype dds on dds.dataset_id = d.id
      left join dataset_subtype ds on ds.id = dds.dataset_subtype_id
      group by d.id
    ) ds on ds.dataset_id = d.id
    -- FIXME: we should be able to do a single query for `dataset_score`
    left join (
      select
        ds.dataset_id,
        ds.score,
        row_number() over (partition by ds.dataset_id order by ds.timestamp desc) row_number
      from dataset_score ds
      where ds.topic = 'freshness'
    ) freshness_score on freshness_score.dataset_id = d.id and freshness_score.row_number = 1
    left join (
      select
        ds.dataset_id,
        ds.score,
        row_number() over (partition by ds.dataset_id order by ds.timestamp desc) row_number
      from dataset_score ds
      where ds.topic = 'availability'
    ) availability_score on availability_score.dataset_id = d.id and availability_score.row_number = 1
    left join (
      select
        ds.dataset_id,
        ds.score,
        row_number() over (partition by ds.dataset_id order by ds.timestamp desc) row_number
      from dataset_score ds
      where ds.topic = 'compliance'
    ) compliance_score on compliance_score.dataset_id = d.id and compliance_score.row_number = 1
    """)
  end
end
