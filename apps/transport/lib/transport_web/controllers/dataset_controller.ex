defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  alias DB.{AOM, Commune, Dataset, DatasetGeographicView, Region, Repo}
  import Ecto.Query

  import TransportWeb.DatasetView,
    only: [availability_number_days: 0, days_notifications_sent: 0, max_nb_history_resources: 0]

  import Phoenix.HTML
  require Logger

  plug(:assign_current_contact when action in [:details])

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params, true)

  @spec list_datasets(Plug.Conn.t(), map(), boolean) :: Plug.Conn.t()
  def list_datasets(%Plug.Conn{} = conn, %{} = params, count_by_region \\ false) do
    conn =
      case count_by_region do
        true -> assign(conn, :regions, get_regions(params))
        false -> conn
      end

    datasets = get_datasets(params)

    conn
    |> assign(:datasets, datasets)
    |> assign(:types, get_types(params))
    |> assign(:licences, get_licences(params))
    |> assign(:number_realtime_datasets, get_realtime_count(params))
    |> assign(:number_resource_format_datasets, resource_format_count(params))
    |> assign(:order_by, params["order_by"])
    |> assign(:q, Map.get(params, "q"))
    |> put_dataset_heart_values(datasets)
    |> put_empty_message(params)
    |> put_category_custom_message(params)
    |> put_page_title(params)
    |> render("index.html")
  end

  @spec details(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    with {:ok, dataset} <- Dataset.get_by_slug(slug_or_id),
         {:ok, territory} <- Dataset.get_territory(dataset) do
      conn
      |> assign(:dataset, dataset)
      |> assign(:resources_related_files, DB.Dataset.get_resources_related_files(dataset))
      |> assign(:territory, territory)
      |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
      |> assign(:other_datasets, Dataset.get_other_datasets(dataset))
      |> assign(:resources_infos, resources_infos(dataset))
      |> assign(
        :history_resources,
        Transport.History.Fetcher.history_resources(dataset,
          max_records: max_nb_history_resources(),
          preload_validations: true
        )
      )
      |> assign(:latest_resources_history_infos, DB.ResourceHistory.latest_dataset_resources_history_infos(dataset))
      |> assign(:notifications_sent, DB.Notification.recent_reasons_binned(dataset, days_notifications_sent()))
      |> assign_scores(dataset)
      |> assign_is_producer(dataset)
      |> assign_follows_dataset(dataset)
      |> put_status(if dataset.is_active, do: :ok, else: :not_found)
      |> render("details.html")
    else
      {:error, msg} ->
        Logger.error("Could not fetch dataset details: #{msg}")
        redirect_to_slug_or_404(conn, slug_or_id)
    end
  end

  defp assign_follows_dataset(
         %Plug.Conn{assigns: %{current_contact: current_contact}} = conn,
         %DB.Dataset{} = dataset
       ) do
    assign(conn, :follows_dataset, DB.DatasetFollower.follows_dataset?(current_contact, dataset))
  end

  defp assign_is_producer(
         %Plug.Conn{assigns: %{current_contact: current_contact}} = conn,
         %DB.Dataset{organization_id: organization_id}
       ) do
    is_producer =
      if Enum.any?([current_contact, organization_id], &is_nil/1) do
        false
      else
        DB.Contact.base_query()
        |> join(:inner, [contact: c], c in assoc(c, :organizations), as: :organization)
        |> where([contact: c, organization: o], c.id == ^current_contact.id and o.id == ^organization_id)
        |> DB.Repo.exists?()
      end

    assign(conn, :is_producer, is_producer)
  end

  def assign_scores(%Plug.Conn{} = conn, %DB.Dataset{} = dataset) do
    data = DB.DatasetScore.scores_over_last_days(dataset, 30 * 3)

    # See https://hexdocs.pm/vega_lite/
    # and https://vega.github.io/vega-lite/docs/
    scores_chart =
      [width: "container", height: 250]
      |> VegaLite.new()
      |> VegaLite.data_from_values(
        Enum.map(data, fn %DB.DatasetScore{topic: topic, timestamp: timestamp} = ds ->
          %{
            "topic" => DB.DatasetScore.topic_for_humans(topic),
            "score" => DB.DatasetScore.score_for_humans(ds),
            "date" => DateTime.to_date(timestamp)
          }
        end)
      )
      |> VegaLite.mark(:line, interpolate: "step-before", tooltip: true, strokeWidth: 3)
      |> VegaLite.encode_field(:x, "date", type: :temporal)
      |> VegaLite.encode_field(:y, "score", type: :quantitative)
      |> VegaLite.encode_field(:color, "topic", type: :nominal)
      |> VegaLite.config(axis: [grid: false])
      |> VegaLite.to_spec()

    latest_scores =
      data
      |> Enum.reject(fn %DB.DatasetScore{score: score} -> is_nil(score) end)
      |> Enum.group_by(fn %DB.DatasetScore{topic: topic} -> topic end)
      # only keep "last" score + format for humans
      |> Enum.map(fn {topic, scores} -> {topic, scores |> List.last() |> DB.DatasetScore.score_for_humans()} end)
      # make the order deterministic
      |> Enum.sort_by(fn {topic, _score} -> topic end)

    merge_assigns(conn, %{scores_chart: scores_chart, latest_scores: latest_scores})
  end

  def validators_to_use,
    do: [
      Transport.Validators.GTFSTransport,
      Transport.Validators.GTFSRT,
      Transport.Validators.TableSchema,
      Transport.Validators.EXJSONSchema,
      Transport.Validators.GBFSValidator,
      Transport.Validators.NeTEx
    ]

  def resources_infos(dataset) do
    %{
      unavailabilities: unavailabilities(dataset),
      resources_updated_at: DB.Dataset.resources_content_updated_at(dataset),
      validations: DB.MultiValidation.dataset_latest_validation(dataset.id, validators_to_use()),
      gtfs_rt_entities: gtfs_rt_entities(dataset)
    }
  end

  @spec gtfs_rt_entities(Dataset.t()) :: map()
  def gtfs_rt_entities(%Dataset{id: dataset_id, type: "public-transit"}) do
    recent_limit = Transport.Jobs.GTFSRTMetadataJob.datetime_limit()

    DB.Resource.base_query()
    |> join(:inner, [resource: r], rm in DB.ResourceMetadata, on: r.id == rm.resource_id, as: :metadata)
    |> where(
      [resource: r, metadata: rm],
      r.dataset_id == ^dataset_id and r.format == "gtfs-rt" and rm.inserted_at > ^recent_limit
    )
    |> select([metadata: rm], %{resource_id: rm.resource_id, feed_type: fragment("UNNEST(?)", rm.features)})
    |> distinct(true)
    |> DB.Repo.all()
    |> Enum.reduce(%{}, fn %{resource_id: resource_id, feed_type: feed_type}, acc ->
      # See https://hexdocs.pm/elixir/Map.html#update/4
      # > If key is not present in map, default is inserted as the value of key.
      # The default value **will not be passed through the update function**.
      Map.update(acc, resource_id, MapSet.new([feed_type]), fn old_val -> MapSet.put(old_val, feed_type) end)
    end)
  end

  def gtfs_rt_entities(%Dataset{}), do: %{}

  @spec by_aom(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_aom(%Plug.Conn{} = conn, %{"aom" => id} = params) do
    error_msg = dgettext("errors", "AOM %{id} does not exist", id: id)
    by_territory(conn, AOM |> where([a], a.id == ^id), params, error_msg)
  end

  @spec by_region(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_region(%Plug.Conn{} = conn, %{"region" => id} = params) do
    error_msg = dgettext("errors", "Region %{id} does not exist", id: id)

    if System.get_env("DISABLE_DATASET_BY_REGION") == "true" do
      conn
      |> put_status(503)
      |> text("Fonctionnalité désactivée pour le moment.")
    else
      by_territory(conn, Region |> where([r], r.id == ^id), params, error_msg, true)
    end
  end

  @spec by_commune_insee(Plug.Conn.t(), map) :: Plug.Conn.t()
  def by_commune_insee(%Plug.Conn{} = conn, %{"insee_commune" => insee} = params) do
    error_msg =
      dgettext(
        "errors",
        "Impossible to find a city with the insee code %{insee}",
        insee: insee
      )

    by_territory(conn, Commune |> where([c], c.insee == ^insee), params, error_msg)
  end

  defp unavailabilities(%Dataset{id: id, resources: resources}) do
    Transport.Cache.fetch("unavailabilities_dataset_#{id}", fn ->
      resources
      |> Enum.into(%{}, fn resource ->
        {resource.id,
         DB.ResourceUnavailability.availability_over_last_days(
           resource,
           availability_number_days()
         )}
      end)
    end)
  end

  defp by_territory(conn, territory, params, error_msg, count_by_region \\ false) do
    territory
    |> Repo.one()
    |> case do
      nil ->
        error_page(conn, error_msg)

      territory ->
        conn
        |> assign(:territory, territory)
        |> list_datasets(params, count_by_region)
    end
  rescue
    Ecto.Query.CastError -> error_page(conn, error_msg)
  end

  @spec error_page(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defp error_page(conn, msg) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> assign(:custom_message, msg)
    |> render("404.html")
  end

  @spec get_datasets(map()) :: Scrivener.Page.t()
  def get_datasets(params) do
    config = make_pagination_config(params)

    params
    |> Dataset.list_datasets()
    |> preload([:aom, :region])
    |> Repo.paginate(page: config.page_number)
  end

  @spec clean_datasets_query(map(), String.t()) :: Ecto.Query.t()
  defp clean_datasets_query(params, key_to_delete),
    do: params |> Map.delete(key_to_delete) |> Dataset.list_datasets() |> exclude(:preload)

  @spec get_regions(map()) :: [Region.t()]
  def get_regions(params) do
    sub =
      params
      |> clean_datasets_query("region")
      |> exclude(:order_by)
      |> join(:left, [dataset: d], d_geo in DatasetGeographicView, on: d.id == d_geo.dataset_id, as: :geo_view)
      |> select([dataset: d, geo_view: d_geo], %{id: d.id, region_id: d_geo.region_id})

    Region
    |> join(:left, [r], d in subquery(sub), on: d.region_id == r.id)
    |> group_by([r], [r.id, r.nom])
    |> select([r, d], %{nom: r.nom, id: r.id, count: count(d.id, :distinct)})
    |> order_by([r], r.nom)
    |> Repo.all()
  end

  @spec get_licences(map()) :: [%{licence: binary(), count: non_neg_integer()}]
  def get_licences(params) do
    params
    |> clean_datasets_query("licence")
    |> exclude(:order_by)
    |> group_by([d], fragment("cleaned_licence"))
    |> select([d], %{
      licence:
        fragment("case when licence in ('fr-lo', 'lov2') then 'licence-ouverte' else licence end as cleaned_licence"),
      count: count(d.id)
    })
    |> Repo.all()
    # Licence ouverte should be first
    |> Enum.sort_by(&Map.get(%{"licence-ouverte" => 1}, &1.licence, 0), &>=/2)
  end

  @spec get_types(map()) :: [%{type: binary(), msg: binary(), count: non_neg_integer()}]
  def get_types(params) do
    params
    |> clean_datasets_query("type")
    |> exclude(:order_by)
    |> group_by([d], [d.type])
    |> select([d], %{type: d.type, count: count(d.id, :distinct)})
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn res ->
      %{type: res.type, count: res.count, msg: Dataset.type_to_str(res.type)}
    end)
    |> add_current_type(params["type"])
    |> Enum.reject(fn t -> is_nil(t.msg) end)
  end

  def resources_history_csv(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    filename = "historisation-dataset-#{dataset_id}-#{Date.utc_today() |> Date.to_iso8601()}.csv"

    csv_header = [
      "resource_history_id",
      "resource_id",
      "permanent_url",
      "payload",
      "inserted_at"
    ]

    # Stream the query from the database and send 100 rows at a time
    {:ok, conn} =
      DB.Repo.transaction(
        fn ->
          Transport.History.Fetcher.history_resources(
            %DB.Dataset{id: String.to_integer(dataset_id)},
            preload_validations: false,
            fetch_mode: :stream
          )
          |> Stream.map(&build_history_csv_row(csv_header, &1))
          |> Stream.chunk_every(100)
          |> send_csv_response(filename, csv_header, conn)
        end,
        timeout: :timer.seconds(60)
      )

    conn
  end

  defp send_csv_response(chunks, filename, csv_header, %Plug.Conn{} = conn) do
    {:ok, conn} =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s|attachment; filename="#{filename}"|)
      |> send_chunked(:ok)
      |> send_csv_chunk([csv_header])

    Enum.reduce_while(chunks, conn, fn data, conn ->
      case send_csv_chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  defp send_csv_chunk(%Plug.Conn{} = conn, data) do
    chunk(conn, data |> NimbleCSV.RFC4180.dump_to_iodata())
  end

  defp build_history_csv_row(csv_header, %DB.ResourceHistory{
         id: rh_id,
         resource_id: resource_id,
         payload: payload,
         inserted_at: inserted_at
       }) do
    row =
      %{
        "resource_history_id" => rh_id,
        "resource_id" => resource_id,
        "permanent_url" => Map.fetch!(payload, "permanent_url"),
        "payload" => Jason.encode!(payload),
        "inserted_at" => inserted_at
      }

    # Build a row following same order as the CSV header
    Enum.map(csv_header, &Map.fetch!(row, &1))
  end

  defp add_current_type(results, type) do
    case Enum.any?(results, &(&1.type == type)) do
      true -> results
      false -> results ++ [%{type: type, count: 0, msg: Dataset.type_to_str(type)}]
    end
  end

  @spec resource_format_count(map()) :: %{binary() => non_neg_integer()}
  defp resource_format_count(params) do
    result =
      params
      |> clean_datasets_query("format")
      |> exclude(:order_by)
      |> DB.Resource.join_dataset_with_resource()
      |> where([resource: r], not is_nil(r.format))
      |> select([resource: r], %{
        dataset_id: r.dataset_id,
        format: r.format
      })
      |> distinct(true)
      |> DB.Repo.all()

    %{all: result |> Enum.uniq_by(& &1.dataset_id) |> Enum.count()}
    |> Map.merge(result |> Enum.map(& &1.format) |> Enum.frequencies() |> Map.new())
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
  end

  @spec get_realtime_count(map()) :: %{all: non_neg_integer(), true: non_neg_integer()}
  defp get_realtime_count(params) do
    result =
      params
      |> clean_datasets_query("filter")
      |> exclude(:order_by)
      |> group_by([d], d.has_realtime)
      |> select([d], %{has_realtime: d.has_realtime, count: count(d.id, :distinct)})
      |> Repo.all()
      |> Enum.reduce(%{}, fn r, acc -> Map.put(acc, r.has_realtime, r.count) end)

    # return the total number of datasets (all) and the number of real time datasets (true)
    %{all: Map.get(result, true, 0) + Map.get(result, false, 0), true: Map.get(result, true, 0)}
  end

  @spec redirect_to_slug_or_404(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defp redirect_to_slug_or_404(conn, slug_or_id) do
    case Integer.parse(slug_or_id) do
      {_id, ""} ->
        redirect_to_dataset(conn, Repo.get_by(Dataset, id: slug_or_id))

      _ ->
        case Repo.get_by(Dataset, datagouv_id: slug_or_id) do
          %Dataset{} = dataset -> redirect_to_dataset(conn, dataset)
          nil -> find_dataset_from_slug(conn, slug_or_id)
        end
    end
  end

  defp find_dataset_from_slug(%Plug.Conn{} = conn, slug) do
    case DB.DatasetHistory.from_old_dataset_slug(slug) do
      %DB.DatasetHistory{dataset_id: dataset_id} ->
        redirect_to_dataset(conn, Repo.get_by(Dataset, id: dataset_id))

      nil ->
        find_dataset_from_datagouv(conn, slug)
    end
  rescue
    Ecto.MultipleResultsError -> redirect_to_dataset(conn, nil)
  end

  defp find_dataset_from_datagouv(%Plug.Conn{} = conn, slug) do
    case Datagouvfr.Client.Datasets.get(slug) do
      {:ok, %{"id" => datagouv_id}} ->
        redirect_to_dataset(conn, Repo.get_by(Dataset, datagouv_id: datagouv_id))

      _ ->
        redirect_to_dataset(conn, nil)
    end
  end

  @spec redirect_to_dataset(Plug.Conn.t(), Dataset.t() | nil) :: Plug.Conn.t()
  defp redirect_to_dataset(conn, nil) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> render("404.html")
  end

  defp redirect_to_dataset(conn, %Dataset{} = dataset) do
    redirect(conn, to: dataset_path(conn, :details, dataset.slug))
  end

  @spec get_name(Ecto.Queryable.t(), binary()) :: binary()
  defp get_name(territory, id) do
    territory
    |> Repo.get(id)
    |> case do
      nil -> id
      t -> t.nom
    end
  end

  @spec empty_message_by_territory(map()) :: binary()
  defp empty_message_by_territory(%{"aom" => id}) do
    dgettext("page-shortlist", "AOM %{name} has not yet published any datasets", name: get_name(AOM, id))
  end

  defp empty_message_by_territory(%{"region" => id}) do
    dgettext("page-shortlist", "There is no data for region %{name}", name: get_name(Region, id))
  end

  defp empty_message_by_territory(%{"insee_commune" => insee}) do
    name =
      case Repo.get_by(Commune, insee: insee) do
        nil -> insee
        a -> a.nom
      end

    dgettext("page-shortlist", "There is no data for city %{name}", name: name)
  end

  defp empty_message_by_territory(_params), do: dgettext("page-shortlist", "No dataset found")

  @spec put_empty_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp put_empty_message(%Plug.Conn{:assigns => %{:datasets => %{:entries => []}}} = conn, params) do
    case map_size(conn.query_params) do
      0 ->
        message = empty_message_by_territory(params)
        assign(conn, :empty_message, raw(message))

      _ ->
        conn
    end
  end

  defp put_empty_message(conn, _params), do: conn

  @spec put_category_custom_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp put_category_custom_message(conn, params) do
    locale = get_session(conn, :locale)

    case Transport.CustomSearchMessage.get_message(params, locale) do
      nil -> conn
      msg -> assign(conn, :category_custom_message, msg)
    end
  end

  defp put_page_title(conn, %{"region" => region_id} = params) do
    national_region = DB.Region.national()

    # For "region = (National) + modes[]=bus", which correspond to
    # long distance coaches (Flixbus, BlaBlaBus etc.) we don't want
    # to put the region name but instead "Long distance coaches"
    if region_id == to_string(national_region.id) and Map.has_key?(params, "modes") do
      put_page_title(conn, Map.delete(params, "region"))
    else
      assign(
        conn,
        :page_title,
        %{type: dgettext("page-shortlist", "region"), name: get_name(Region, region_id)}
      )
    end
  end

  defp put_page_title(conn, %{"insee_commune" => insee}) do
    name = Repo.get_by!(Commune, insee: insee).nom

    assign(
      conn,
      :page_title,
      %{type: dgettext("page-shortlist", "city"), name: name}
    )
  end

  defp put_page_title(conn, %{"aom" => id}),
    do:
      assign(
        conn,
        :page_title,
        %{type: "AOM", name: get_name(AOM, id)}
      )

  defp put_page_title(%Plug.Conn{request_path: request_path, query_params: query_params} = conn, _) do
    TransportWeb.PageController.home_tiles(conn)
    # Allows to match `?type=foo&filter=has_realtime` otherwise
    # `?type=foo` would match and we would not consider
    # other options.
    |> Enum.sort_by(&String.length(&1.link), :desc)
    |> Enum.find(&tile_matches_query?(&1, MapSet.new(Map.merge(%{"path" => request_path}, query_params))))
    |> case do
      %TransportWeb.PageController.Tile{title: title} ->
        assign(
          conn,
          :page_title,
          %{type: dgettext("page-shortlist", "category"), name: title}
        )

      _ ->
        conn
    end
  end

  defp tile_matches_query?(%TransportWeb.PageController.Tile{link: link}, %MapSet{} = request) do
    uri = link |> URI.new!()
    tile_query = (uri |> Map.fetch!(:query) || "") |> Plug.Conn.Query.decode()
    tile_params = Map.merge(%{"path" => uri.path}, tile_query) |> MapSet.new()

    MapSet.subset?(tile_params, request)
  end

  defp put_dataset_heart_values(%Plug.Conn{assigns: %{current_user: current_user}} = conn, datasets) do
    if is_nil(current_user) do
      conn
    else
      assign(conn, :dataset_heart_values, dataset_heart_values(current_user, datasets))
    end
  end

  @doc """
  Compute, for each dataset displayed on the current page, what the heart icon$
  should look like.

  The current user can be a producer/follow the dataset or nothing (not a producer and not following it).
  """
  def dataset_heart_values(%{"id" => datagouv_user_id} = _current_user, datasets) do
    dataset_ids = Enum.map(datasets, & &1.id)

    contact_org_ids =
      DB.Contact.base_query()
      |> join(:left, [contact: c], c in assoc(c, :organizations), as: :organization)
      |> where([contact: c], c.datagouv_user_id == ^datagouv_user_id)
      |> select([organization: o], o.id)
      |> DB.Repo.all()

    followed_dataset_ids =
      DB.Contact.base_query()
      |> join(:left, [contact: c], c in assoc(c, :followed_datasets), as: :dataset)
      |> where([contact: c, dataset: d], c.datagouv_user_id == ^datagouv_user_id and d.id in ^dataset_ids)
      |> select([dataset: d], d.id)
      |> DB.Repo.all()

    Map.new(datasets, fn %DB.Dataset{id: dataset_id, organization_id: organization_id} ->
      value =
        cond do
          organization_id in contact_org_ids -> :producer
          dataset_id in followed_dataset_ids -> :following
          true -> nil
        end

      {dataset_id, value}
    end)
  end

  defp assign_current_contact(%Plug.Conn{assigns: %{current_user: current_user}} = conn, _options) do
    current_contact =
      if is_nil(current_user) do
        nil
      else
        DB.Contact
        |> DB.Repo.get_by!(datagouv_user_id: Map.fetch!(current_user, "id"))
        |> DB.Repo.preload(:default_tokens)
      end

    assign(conn, :current_contact, current_contact)
  end
end
