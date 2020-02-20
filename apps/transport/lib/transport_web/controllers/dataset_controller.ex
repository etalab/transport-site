defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  alias Datagouvfr.Client.{CommunityResources, Datasets, Discussions, Reuses}
  alias DB.{AOM, Commune, Dataset, DatasetGeographicView, Region, Repo}
  import Ecto.Query
  import Phoenix.HTML
  import Phoenix.HTML.Link
  require Logger

  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params)

  def list_datasets(%Plug.Conn{} = conn, %{} = params) do
    conn
    |> assign(:datasets, get_datasets(params))
    |> assign(:regions, get_regions(params))
    |> assign(:types, get_types(params))
    |> assign(:order_by, params["order_by"])
    |> assign(:q, Map.get(params, "q"))
    |> put_special_message(params)
    |> put_empty_message(params)
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

  def by_aom(%Plug.Conn{} = conn, %{"aom" => id} = params) do
    error_msg = dgettext("errors", "AOM %{id} does not exist", id: id)

    try do
      AOM
      |> where([a], a.id == ^id)
      |> Repo.exists?()
      |> case do
        false ->
          error_page(conn, error_msg)

        true ->
          list_datasets(conn, params)
      end
    rescue
      Ecto.Query.CastError -> error_page(conn, error_msg)
    end
  end

  def by_region(%Plug.Conn{} = conn, %{"region" => id} = params) do
    error_msg = dgettext("errors", "Region %{id} does not exist", id: id)

    try do
      Region
      |> where([r], r.id == ^id)
      |> Repo.exists?()
      |> case do
        false ->
          error_page(conn, error_msg)

        true ->
          list_datasets(conn, params)
      end
    rescue
      Ecto.Query.CastError -> error_page(conn, error_msg)
    end
  end

  def by_commune_insee(%Plug.Conn{} = conn, %{"insee_commune" => insee} = params) do
    Commune
    |> where([c], c.insee == ^insee)
    |> Repo.exists?()
    |> case do
      false ->
        message =
          dgettext(
            "errors",
            "Impossible to find a city with the insee code %{insee}",
            insee: insee
          )

        error_page(conn, message)

      true ->
        list_datasets(conn, params)
    end
  end

  defp error_page(conn, msg) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> assign(:reason, raw(msg))
    |> render("404.html")
  end

  defp get_datasets(params) do
    config = make_pagination_config(params)

    params
    |> Dataset.list_datasets()
    |> preload([:aom, :region])
    |> Repo.paginate(page: config.page_number)
  end

  defp clean_datasets_query(params), do: params |> Dataset.list_datasets() |> exclude(:preload)

  defp get_regions(%{"tags" => _tags}) do
    # for tags, we do not filter the datasets since it causes a non valid sql query
    sub =
      %{}
      |> clean_datasets_query()
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

  defp get_regions(params) do
    sub =
      params
      |> clean_datasets_query()
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

  defp get_types(params) do
    params
    |> clean_datasets_query()
    |> exclude(:order_by)
    |> select([d], d.type)
    |> distinct(true)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn type -> %{type: type, msg: Dataset.type_to_str(type)} end)
    |> Enum.reject(fn t -> is_nil(t.msg) end)
  end

  defp redirect_to_slug_or_404(conn, %Dataset{} = dataset) do
    redirect(conn, to: dataset_path(conn, :details, dataset.slug))
  end

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

  defp put_special_message(conn, %{"filter" => "has_realtime", "page" => page})
       when page != 1,
       do: conn

  defp put_special_message(conn, %{"filter" => "has_realtime"}) do
    realtime_link =
      "page-shortlist"
      |> dgettext("here")
      |> link(to: page_path(conn, :real_time))
      |> safe_to_string()

    message =
      dgettext(
        "page-shortlist",
        "More information about realtime %{realtime_link}",
        realtime_link: realtime_link
      )

    assign(conn, :special_message, raw(message))
  end

  defp put_special_message(conn, _params), do: conn

  defp put_empty_message(%Plug.Conn{:assigns => %{:datasets => %{:entries => []}}} = conn, %{
         "aom" => id
       }) do
    name =
      case Repo.get(AOM, id) do
        nil -> id
        a -> a.nom
      end

    message = dgettext("page-shortlist", "AOM %{name} has not yet published any datasets", name: name)

    conn
    |> assign(:empty_message, raw(message))
  end

  defp put_empty_message(%Plug.Conn{:assigns => %{:datasets => %{:entries => []}}} = conn, %{
         "region" => id
       }) do
    name =
      case Repo.get(Region, id) do
        nil -> id
        a -> a.nom
      end

    message = dgettext("page-shortlist", "There is no data for region %{name}", name: name)

    conn
    |> assign(:empty_message, raw(message))
  end

  defp put_empty_message(%Plug.Conn{:assigns => %{:datasets => %{:entries => []}}} = conn, %{
         "insee_commune" => insee
       }) do
    name =
      case Repo.get_by(Commune, insee: insee) do
        nil -> insee
        a -> a.nom
      end

    message = dgettext("page-shortlist", "There is no data for city %{name}", name: name)

    conn
    |> assign(:empty_message, raw(message))
  end

  defp put_empty_message(%Plug.Conn{:assigns => %{:datasets => %{:entries => []}}} = conn, _params) do
    message = dgettext("page-shortlist", "No dataset found")

    conn
    |> assign(:empty_message, raw(message))
  end

  defp put_empty_message(conn, _params), do: conn
end
