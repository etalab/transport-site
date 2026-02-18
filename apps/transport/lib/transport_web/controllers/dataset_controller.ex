defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  import Ecto.Query

  import TransportWeb.DatasetView,
    only: [availability_number_days: 0, days_notifications_sent: 0, max_nb_history_resources: 0]

  import Phoenix.HTML
  require Logger

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params, true)

  @db_filter_fns %{
    "departement" => &DB.Dataset.filter_by_departement/2,
    "epci" => &DB.Dataset.filter_by_epci/2,
    "commune" => &DB.Dataset.filter_by_commune/2,
    "q" => &DB.Dataset.filter_by_fulltext/2,
    "features" => &DB.Dataset.filter_by_feature/2
  }
  @db_only_filters Map.keys(@db_filter_fns)

  @spec list_datasets(Plug.Conn.t(), map(), boolean) :: Plug.Conn.t()
  def list_datasets(%Plug.Conn{} = conn, %{} = params, count_by_region \\ false) do
    index = Transport.DatasetIndex.get()
    dataset_ids = dataset_ids_for(index, params)

    datasets =
      DB.Dataset.base_query()
      |> preload(:resources)
      |> where([d], d.id in ^dataset_ids)
      |> order_by([d], fragment("array_position(?, ?)", ^dataset_ids, d.id))
      |> preload_spatial_areas()
      |> DB.Repo.paginate(page: make_pagination_config(params).page_number)

    conn
    |> maybe_assign_regions(count_by_region, index, dataset_ids)
    |> assign(:datasets, datasets)
    |> assign_facets(index, dataset_ids, params)
    |> put_dataset_heart_values(datasets)
    |> put_empty_message(params)
    |> put_category_custom_message(params)
    |> put_page_title(params)
    |> render("index.html")
  end

  defp assign_facets(conn, index, dataset_ids, params) do
    conn
    |> assign(:types, Transport.DatasetIndex.types(index, dataset_ids))
    |> assign(:licences, Transport.DatasetIndex.licences(index, dataset_ids))
    |> assign(:number_realtime_datasets, Transport.DatasetIndex.realtime_count(index, dataset_ids))
    |> assign(:number_resource_format_datasets, Transport.DatasetIndex.resource_format_count(index, dataset_ids))
    |> assign(:subtypes, subtypes_facet(index, dataset_ids, params))
    |> assign(:order_by, params["order_by"])
    |> assign(:q, params["q"])
  end

  defp maybe_assign_regions(conn, false, _index, _dataset_ids), do: conn

  defp maybe_assign_regions(conn, true, index, dataset_ids),
    do: assign(conn, :regions, Transport.DatasetIndex.regions(index, dataset_ids))

  defp subtypes_facet(index, dataset_ids, %{"type" => type} = _params) do
    Transport.DatasetIndex.subtypes(index, dataset_ids, type)
  end

  defp subtypes_facet(_index, _dataset_ids, _params), do: %{all: 0, subtypes: []}

  @spec details(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    case DB.Dataset.get_by_slug(slug_or_id) do
      {:ok, %DB.Dataset{} = dataset} ->
        conn
        |> assign(:dataset, dataset)
        |> assign(:resources_related_files, DB.Dataset.get_resources_related_files(dataset))
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> assign(:resources_infos, resources_infos(dataset))
        |> assign(
          :history_resources,
          Transport.History.Fetcher.history_resources(dataset,
            max_records: max_nb_history_resources(),
            preload_validations: true,
            only_metadata: true
          )
        )
        |> assign(:latest_resources_history_infos, DB.ResourceHistory.latest_dataset_resources_history_infos(dataset))
        |> assign(:notifications_sent, DB.Notification.recent_reasons(dataset, days_notifications_sent()))
        |> assign_scores(dataset)
        |> assign_is_producer(dataset)
        |> assign_follows_dataset(dataset)
        |> put_status(if dataset.is_active, do: :ok, else: :not_found)
        |> render("details.html")

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
    do: Transport.ValidatorsSelection.validators_for_feature(:dataset_controller)

  def resources_infos(dataset) do
    %{
      unavailabilities: unavailabilities(dataset),
      resources_updated_at: DB.Dataset.resources_content_updated_at(dataset),
      validations: DB.MultiValidation.dataset_latest_validation(dataset.id, validators_to_use()),
      gtfs_rt_entities: gtfs_rt_entities(dataset)
    }
  end

  @spec gtfs_rt_entities(DB.Dataset.t()) :: map()
  def gtfs_rt_entities(%DB.Dataset{id: dataset_id, type: "public-transit"}) do
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

  def gtfs_rt_entities(%DB.Dataset{}), do: %{}

  @spec by_region(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_region(%Plug.Conn{} = conn, %{"region" => insee} = params) do
    error_msg = dgettext("errors", "Region %{insee} does not exist", insee: insee)

    if System.get_env("DISABLE_DATASET_BY_REGION") == "true" do
      conn
      |> put_status(503)
      |> text("Fonctionnalité désactivée pour le moment.")
    else
      by_territory(conn, DB.Region |> where([r], r.insee == ^insee), params, error_msg, true)
    end
  end

  @spec by_departement_insee(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_departement_insee(%Plug.Conn{} = conn, %{"departement" => insee} = params) do
    error_msg = dgettext("errors", "Department %{insee} does not exist", insee: insee)
    by_territory(conn, DB.Departement |> where([d], d.insee == ^insee), params, error_msg)
  end

  @spec by_epci(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_epci(%Plug.Conn{} = conn, %{"epci" => insee} = params) do
    error_msg = dgettext("errors", "EPCI %{insee} does not exist", insee: insee)
    by_territory(conn, DB.EPCI |> where([a], a.insee == ^insee), params, error_msg)
  end

  @spec by_commune_insee(Plug.Conn.t(), map) :: Plug.Conn.t()
  def by_commune_insee(%Plug.Conn{} = conn, %{"commune" => insee} = params) do
    error_msg =
      dgettext(
        "errors",
        "Impossible to find a city with the insee code %{insee}",
        insee: insee
      )

    by_territory(conn, DB.Commune |> where([c], c.insee == ^insee), params, error_msg)
  end

  def by_offer(%Plug.Conn{} = conn, params) do
    conn |> list_datasets(params, _count_by_region = false)
  end

  defp unavailabilities(%DB.Dataset{id: id, resources: resources}) do
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
    |> DB.Repo.one()
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

  defp dataset_ids_for(index, params) do
    memory_ids = Transport.DatasetIndex.filter_dataset_ids(index, params)
    db_only_params = Map.take(params, @db_only_filters)
    order_and_refine(memory_ids, index, params, db_only_params)
  end

  # When the search does not include "db params" we can filter and order using only the memory index
  defp order_and_refine(memory_ids, index, params, db_only_params) when db_only_params == %{} do
    Transport.DatasetIndex.order_dataset_ids(memory_ids, index, params)
  end

  defp order_and_refine(memory_ids, _index, params, db_only_params) do
    DB.Dataset.base_query()
    |> where([dataset: d], d.id in ^memory_ids)
    |> apply_db_only_filters(db_only_params)
    |> DB.Dataset.order_datasets(params)
    |> select([dataset: d], d.id)
    |> DB.Repo.all()
  end

  defp apply_db_only_filters(%Ecto.Query{} = query, db_only_params) do
    Enum.reduce(db_only_params, query, fn {key, _value}, acc ->
      case Map.fetch(@db_filter_fns, key) do
        {:ok, filter_fn} -> filter_fn.(acc, db_only_params)
        :error -> acc
      end
    end)
  end

  defp preload_spatial_areas(query) do
    DB.AdministrativeDivision
    |> select([a], struct(a, [:type, :nom]))
    |> then(&preload(query, declarative_spatial_areas: ^&1))
  end

  def resources_history_csv(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    dataset_id = String.to_integer(dataset_id)

    DB.FeatureUsage.insert!(
      :download_resource_history,
      get_in(conn.assigns.current_contact.id),
      %{dataset_id: dataset_id}
    )

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
            %DB.Dataset{id: dataset_id},
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

  @spec redirect_to_slug_or_404(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defp redirect_to_slug_or_404(conn, slug_or_id) do
    case Integer.parse(slug_or_id) do
      {_id, ""} ->
        redirect_to_dataset(conn, DB.Repo.get_by(DB.Dataset, id: slug_or_id))

      _ ->
        case DB.Repo.get_by(DB.Dataset, datagouv_id: slug_or_id) do
          %DB.Dataset{} = dataset -> redirect_to_dataset(conn, dataset)
          nil -> find_dataset_from_slug(conn, slug_or_id)
        end
    end
  end

  defp find_dataset_from_slug(%Plug.Conn{} = conn, slug) do
    case DB.DatasetHistory.from_old_dataset_slug(slug) do
      %DB.DatasetHistory{dataset_id: dataset_id} ->
        redirect_to_dataset(conn, DB.Repo.get_by(DB.Dataset, id: dataset_id))

      nil ->
        find_dataset_from_datagouv(conn, slug)
    end
  rescue
    Ecto.MultipleResultsError -> redirect_to_dataset(conn, nil)
  end

  defp find_dataset_from_datagouv(%Plug.Conn{} = conn, slug) do
    case Datagouvfr.Client.Datasets.get(slug) do
      {:ok, %{"id" => datagouv_id}} ->
        redirect_to_dataset(conn, DB.Repo.get_by(DB.Dataset, datagouv_id: datagouv_id))

      _ ->
        redirect_to_dataset(conn, nil)
    end
  end

  @spec redirect_to_dataset(Plug.Conn.t(), DB.Dataset.t() | nil) :: Plug.Conn.t()
  defp redirect_to_dataset(conn, nil) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> render("404.html")
  end

  defp redirect_to_dataset(conn, %DB.Dataset{} = dataset) do
    redirect(conn, to: dataset_path(conn, :details, dataset.slug))
  end

  @spec get_name(Ecto.Queryable.t(), binary()) :: binary()
  defp get_name(DB.Offer, identifiant_offre) do
    DB.Offer
    |> where([o], o.identifiant_offre == ^identifiant_offre)
    |> select([o], o.nom_commercial)
    |> DB.Repo.one!()
  end

  defp get_name(territory, insee) do
    territory
    |> DB.Repo.get_by(insee: insee)
    |> case do
      nil -> insee
      t -> t.nom
    end
  end

  @spec empty_message_by_territory(map()) :: binary()
  defp empty_message_by_territory(%{"epci" => insee}) do
    dgettext("page-shortlist", "EPCI %{name} has not yet published any datasets", name: get_name(DB.EPCI, insee))
  end

  defp empty_message_by_territory(%{"region" => insee}) do
    dgettext("page-shortlist", "There is no data for region %{name}", name: get_name(DB.Region, insee))
  end

  defp empty_message_by_territory(%{"commune" => insee}) do
    dgettext("page-shortlist", "There is no data for city %{name}", name: get_name(DB.Region, insee))
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

  defp put_page_title(conn, %{"region" => insee} = params) do
    # For "region = (National) + modes[]=bus", which correspond to
    # long distance coaches (Flixbus, BlaBlaBus etc.) we don't want
    # to put the region name but instead "Long distance coaches"
    if insee == DB.Region.national().insee and Map.has_key?(params, "modes") do
      put_page_title(conn, Map.delete(params, "region"))
    else
      assign(
        conn,
        :page_title,
        %{type: dgettext("page-shortlist", "region"), name: get_name(DB.Region, insee)}
      )
    end
  end

  defp put_page_title(conn, %{"commune" => insee}) do
    assign(
      conn,
      :page_title,
      %{type: dgettext("page-shortlist", "city"), name: get_name(DB.Commune, insee)}
    )
  end

  defp put_page_title(conn, %{"departement" => insee}) do
    assign(
      conn,
      :page_title,
      %{type: dgettext("page-shortlist", "department"), name: get_name(DB.Departement, insee)}
    )
  end

  defp put_page_title(conn, %{"epci" => insee}),
    do:
      assign(
        conn,
        :page_title,
        %{type: "EPCI", name: get_name(DB.EPCI, insee)}
      )

  defp put_page_title(conn, %{"identifiant_offre" => identifiant_offre}),
    do:
      assign(
        conn,
        :page_title,
        %{
          type: dgettext("page-shortlist", "transport offer"),
          name: get_name(DB.Offer, identifiant_offre)
        }
      )

  defp put_page_title(conn, %{"format" => format}),
    do:
      assign(
        conn,
        :page_title,
        %{
          type: dgettext("page-shortlist", "data format"),
          name: format
        }
      )

  defp put_page_title(%Plug.Conn{request_path: request_path, query_params: query_params} = conn, _) do
    # We use the home tiles to associate the URL params to a title, see doc of the function
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
end
