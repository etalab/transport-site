defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  alias Datagouvfr.Client.{CommunityResources, Datasets, Discussions, Reuses}
  alias DB.{AOM, Commune, Dataset, Region, Repo}
  import Ecto.Query
  import Phoenix.HTML
  require Logger

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params)

  @spec list_datasets(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_datasets(%Plug.Conn{} = conn, %{} = params) do
    conn
    |> assign(:datasets, get_datasets(params))
    |> assign(:types, get_types(params))
    |> assign(:number_realtime_datasets, get_realtime_count(params))
    |> assign(:order_by, params["order_by"])
    |> assign(:q, Map.get(params, "q"))
    |> put_empty_message(params)
    |> put_custom_context(params)
    |> put_page_title(params)
    |> render("index.html")
  end

  @spec details(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    with {:ok, dataset} <- Dataset.get_by_slug(slug_or_id),
         {:ok, territory} <- Dataset.get_territory(dataset),
         {:ok, community_ressources} <- CommunityResources.get(dataset.datagouv_id),
         {:ok, reuses} <- Reuses.get(dataset) do
      conn
      |> assign(:dataset, dataset)
      |> assign(:community_ressources, community_ressources)
      |> assign(:territory, territory)
      |> assign(:discussions, Discussions.get(dataset.datagouv_id))
      |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
      |> assign(:is_subscribed, Datasets.current_user_subscribed?(conn, dataset.datagouv_id))
      |> assign(:reuses, reuses)
      |> assign(:other_datasets, Dataset.get_other_datasets(dataset))
      |> assign(:history_resources, Dataset.history_resources(dataset))
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
    by_territory(conn, Region |> where([r], r.id == ^id), params, error_msg)
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

  defp by_territory(conn, territory, params, error_msg) do
    territory
    |> Repo.one()
    |> case do
      nil ->
        error_page(conn, error_msg)

      territory ->
        conn
        |> assign(:territory, territory)
        |> list_datasets(params)
    end
  rescue
    Ecto.Query.CastError -> error_page(conn, error_msg)
  end

  @spec error_page(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defp error_page(conn, msg) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> assign(:reason, msg)
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

  @spec redirect_to_slug_or_404(Plug.Conn.t(), number() | binary()) :: Plug.Conn.t()

  defp redirect_to_slug_or_404(conn, nil) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> render("404.html")
  end

  defp redirect_to_slug_or_404(conn, slug_or_id) when is_integer(slug_or_id) do
    redirect_to_slug_or_404(conn, Repo.get_by(Dataset, id: slug_or_id))
  end

  defp redirect_to_slug_or_404(conn, slug_or_id) do
    redirect_to_slug_or_404(conn, Repo.get_by(Dataset, datagouv_id: slug_or_id))
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
        assign(conn, :empty_message, raw(dgettext("page-shortlist", "No results")))
    end
  end

  defp put_empty_message(conn, _params), do: conn

  @spec put_custom_context(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp put_custom_context(conn, %{"filter" => "has_realtime"}),
    do: assign(conn, :custom_context, "_realtime.html")

  defp put_custom_context(conn, %{"type" => "addresses"}),
    do: assign(conn, :custom_context, "_addresses.html")

  defp put_custom_context(conn, _), do: conn

  defp put_page_title(conn, %{"region" => id}),
    do:
      assign(
        conn,
        :page_title,
        dgettext("page-shortlist", "Datasets for the region %{region}", region: get_name(Region, id))
      )

  defp put_page_title(conn, %{"insee_commune" => insee}) do
    name = Repo.get_by!(Commune, insee: insee).nom

    assign(
      conn,
      :page_title,
      dgettext("page-shortlist", "Datasets for the city %{name}", name: name)
    )
  end

  defp put_page_title(conn, %{"aom" => id}),
    do:
      assign(
        conn,
        :page_title,
        dgettext("page-shortlist", "Datasets for the aom %{aom}", aom: get_name(AOM, id))
      )

  defp put_page_title(conn, _), do: conn
end
