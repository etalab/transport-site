defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  alias Datagouvfr.Client.{CommunityResources, Datasets, Discussions, Reuses}
  alias Transport.{AOM, Dataset, Region, Repo}
  import Ecto.Query
  import Phoenix.HTML
  import Phoenix.HTML.Link
  require Logger

  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params)

  def list_datasets(%Plug.Conn{} = conn, %{} = params) do
    params = Map.put_new(params, "order_by", "most_recent")

    conn
    |> assign(:datasets, get_datasets(params))
    |> assign(:regions, get_regions(params))
    |> assign(:types, get_types(params))
    |> assign(:order_by, params["order_by"])
    |> assign(:q, Map.get(params, "q"))
    |> put_special_message(params)
    |> render("index.html")
  end

  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    with dataset when not is_nil(dataset) <- Dataset.get_by(slug: slug_or_id, preload: true),
        organization when not is_nil(organization) <- Dataset.get_organization(dataset),
        {_, community_ressources} <- CommunityResources.get(dataset.datagouv_id),
        {_, reuses} <- Reuses.get(conn, dataset) do
        conn
        |> assign(:dataset, dataset)
        |> assign(:community_ressources, community_ressources)
        |> assign(:organization, organization)
        |> assign(:discussions, Discussions.get(conn, dataset.datagouv_id))
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> assign(:is_subscribed, Datasets.current_user_subscribed?(conn, dataset.datagouv_id))
        |> assign(:reuses, reuses)
        |> assign(:other_datasets, Dataset.get_other_datasets(dataset))
        |> put_status(if dataset.is_active do :ok else :not_found end)
        |> render("details.html")
    else
      nil ->
        redirect_to_slug_or_404(conn, slug_or_id)
    end
  end

  def by_aom(%Plug.Conn{} = conn, %{"commune" => _} = params), do: list_datasets(conn, params)
  def by_region(%Plug.Conn{} = conn, %{"region" => _} = params), do: list_datasets(conn, params)

  defp get_datasets(params) do
    config = make_pagination_config(params)
    select = [
      :id, :description, :licence, :logo, :spatial,
      :title, :slug, :aom_id, :region_id, :type
    ]

    params
    |> Dataset.list_datasets(select)
    |> preload([:aom, :region])
    |> Repo.paginate(page: config.page_number)
  end

  defp clean_datasets_query(params), do: params |> Dataset.list_datasets([]) |> exclude(:preload)
  defp get_regions(params) do
    sub = params
    |> clean_datasets_query()
    |> exclude(:order_by)
    |> join(:left, [d], a in AOM, on: d.aom_id == a.id)
    |> select([d, a], %{id: d.id, region_id: coalesce(d.region_id, a.region_id)})

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
    |> put_status(:internal_server_error)
    |> put_view(ErrorView)
    |> render("404.html")
  end

  defp redirect_to_slug_or_404(conn, slug_or_id) when is_integer(slug_or_id) do
    redirect_to_slug_or_404(conn, Repo.get_by(Dataset, [id: slug_or_id]))
  end

  defp redirect_to_slug_or_404(conn, slug_or_id) do
    redirect_to_slug_or_404(conn, Repo.get_by(Dataset, [datagouv_id: slug_or_id]))
  end

  defp put_special_message(conn, %{"filter" => "has_realtime", "page" => page})
    when page != 1, do: conn
  defp put_special_message(conn, %{"filter" => "has_realtime"}) do
    realtime_link =
      "page-shortlist"
      |> dgettext("here")
      |> link(to: page_path(conn, :single_page, "real_time"))
      |> safe_to_string()

    message = dgettext(
      "page-shortlist",
      "More information about realtime %{realtime_link}",
      realtime_link: realtime_link
    )

    assign(conn, :special_message, raw(message))
  end
  defp put_special_message(conn, _params), do: conn
end
