defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  alias Datagouvfr.Client.{Datasets, Discussions, Reuses}
  alias DB.{AOM, Commune, Dataset, DatasetGeographicView, Region, Repo}
  import Ecto.Query
  import TransportWeb.DatasetView, only: [availability_number_days: 0]
  import Phoenix.HTML
  require Logger

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params, true)

  @spec list_datasets(Plug.Conn.t(), map(), boolean) :: Plug.Conn.t()
  def list_datasets(%Plug.Conn{} = conn, %{} = params, count_by_region \\ false) do
    conn =
      case count_by_region do
        true -> assign(conn, :regions, get_regions(params))
        false -> conn
      end

    conn
    |> assign(:datasets, get_datasets(params))
    |> assign(:types, get_types(params))
    |> assign(:number_realtime_datasets, get_realtime_count(params))
    |> assign(:order_by, params["order_by"])
    |> assign(:q, Map.get(params, "q"))
    |> put_empty_message(params)
    |> put_category_custom_message(params)
    |> put_page_title(params)
    |> render("index.html")
  end

  @spec details(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    with {:ok, dataset} <- Dataset.get_by_slug(slug_or_id),
         {:ok, territory} <- Dataset.get_territory(dataset) do
      # in case data.gouv datagouv is down, datasets pages should still be available on our site
      reuses_assign =
        case Reuses.get(dataset) do
          {:ok, reuses} -> [reuses: reuses, fetch_reuses_error: false]
          _ -> [reuses: %{}, fetch_reuses_error: true]
        end

      conn
      |> assign(:dataset, dataset)
      |> assign(:resources_related_files, DB.Dataset.get_resources_related_files(dataset))
      |> assign(:territory, territory)
      |> assign(:discussions, Discussions.get(dataset.datagouv_id))
      |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
      |> assign(:is_subscribed, Datasets.current_user_subscribed?(conn, dataset.datagouv_id))
      |> merge_assigns(reuses_assign)
      |> assign(:other_datasets, Dataset.get_other_datasets(dataset))
      |> assign(:unavailabilities, unavailabilities(dataset))
      |> assign(:history_resources, Transport.History.Fetcher.history_resources(dataset))
      |> put_status(if dataset.is_active, do: :ok, else: :not_found)
      |> render("details.html")
    else
      {:error, msg} ->
        Logger.error("Could not fetch dataset details: #{msg}")
        redirect_to_slug_or_404(conn, slug_or_id)

      nil ->
        redirect_to_slug_or_404(conn, slug_or_id)
    end
  end

  @spec by_aom(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_aom(%Plug.Conn{} = conn, %{"aom" => id} = params) do
    error_msg = dgettext("errors", "AOM %{id} does not exist", id: id)
    by_territory(conn, AOM |> where([a], a.id == ^id), params, error_msg)
  end

  @spec by_region(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_region(%Plug.Conn{} = conn, %{"region" => id} = params) do
    error_msg = dgettext("errors", "Region %{id} does not exist", id: id)
    by_territory(conn, Region |> where([r], r.id == ^id), params, error_msg, true)
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
    Transport.Cache.API.fetch("unavailabilities_dataset_#{id}", fn ->
      resources
      |> Enum.into(%{}, fn resource ->
        {resource.id, DB.ResourceUnavailability.availability_over_last_days(resource, availability_number_days())}
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
  defp get_datasets(params) do
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
  defp get_regions(params) do
    sub =
      params
      |> clean_datasets_query("region")
      |> exclude(:order_by)
      |> join(:left, [d], d_geo in DatasetGeographicView, on: d.id == d_geo.dataset_id)
      |> select([d, d_geo], %{id: d.id, region_id: d_geo.region_id})

    Region
    |> join(:left, [r], d in subquery(sub), on: d.region_id == r.id)
    |> group_by([r], [r.id, r.nom])
    |> select([r, d], %{nom: r.nom, id: r.id, count: count(d.id)})
    |> order_by([r], r.nom)
    |> Repo.all()
  end

  @spec get_types(map()) :: [%{type: binary(), msg: binary(), count: integer}]
  defp get_types(params) do
    params
    |> clean_datasets_query("type")
    |> exclude(:order_by)
    |> group_by([d], [d.type])
    |> select([d], %{type: d.type, count: count(d.type)})
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn res -> %{type: res.type, count: res.count, msg: Dataset.type_to_str(res.type)} end)
    |> add_current_type(params["type"])
    |> Enum.reject(fn t -> is_nil(t.msg) end)
  end

  defp add_current_type(results, type) do
    case Enum.any?(results, &(&1.type == type)) do
      true -> results
      false -> results ++ [%{type: type, count: 0, msg: Dataset.type_to_str(type)}]
    end
  end

  @spec get_realtime_count(map()) :: %{all: integer, true: integer}
  defp get_realtime_count(params) do
    result =
      params
      |> clean_datasets_query("filter")
      |> exclude(:order_by)
      |> group_by([d], d.has_realtime)
      |> select([d], %{has_realtime: d.has_realtime, count: count()})
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
        redirect_to_dataset(conn, Repo.get_by(Dataset, datagouv_id: slug_or_id))
    end
  end

  @spec redirect_to_dataset(Plug.Conn.t(), %Dataset{} | nil) :: Plug.Conn.t()
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

  defp put_page_title(conn, %{"region" => id}),
    do:
      assign(
        conn,
        :page_title,
        %{type: dgettext("page-shortlist", "region"), name: get_name(Region, id)}
      )

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

  defp put_page_title(conn, %{"type" => t} = f) when map_size(f) == 1,
    do:
      assign(
        conn,
        :page_title,
        %{type: dgettext("page-shortlist", "category"), name: Dataset.type_to_str(t)}
      )

  defp put_page_title(conn, _), do: conn
end
