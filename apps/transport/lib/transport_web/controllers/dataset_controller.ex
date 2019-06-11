defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Datagouvfr.{Authentication, Client}
  alias Datagouvfr.Client.Datasets
  alias Transport.{AOM, Dataset, Region, Repo}
  import Ecto.Query
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
    |> render("index.html")
  end

  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    with dataset <- Dataset.get_by(slug: slug_or_id),
        aom <- Repo.get(AOM, dataset.aom_id),
        {_, community_ressources} <- Client.get_community_resources(conn, dataset.datagouv_id),
        other_datasets <- Dataset.get_same_aom(dataset) do
        conn
        |> assign(:dataset, dataset)
        |> assign(:discussions, Client.get_discussions(conn, dataset.datagouv_id))
        |> assign(:community_ressources, community_ressources)
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> assign(:is_subscribed, Datasets.current_user_subscribed?(conn, dataset.datagouv_id))
        |> assign(:reuses, Client.get_reuses(conn, %{"dataset_id" => dataset.datagouv_id}))
        |> assign(:aom, aom)
        |> assign(:other_datasets, other_datasets)
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
    select = [:id, :description, :licence, :logo, :spatial, :title, :slug]

    params
    |> Dataset.list_datasets(select)
    |> Repo.paginate(page: config.page_number)
  end

  defp clean_datasets_query(params), do: params |> Dataset.list_datasets([]) |> exclude(:preload)
  defp get_regions(params) do
    sub = params
    |> clean_datasets_query()
    |> select([d], %{region_id: d.region_id, aom_id: d.aom_id})

    aoms_sub = AOM
    |> join(:inner, [a], d in subquery(sub), on: d.aom_id == a.id)
    |> select([a], %{region_id: a.region_id})

    Region
    |> join(:inner, [r], d in subquery(sub), on: d.region_id == r.id)
    |> join(:inner, [r], d in subquery(aoms_sub), on: d.region_id == r.id)
    |> select([r], %Region{nom: r.nom, id: r.id})
    |> distinct(true)
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
    |> render(ErrorView, "404.html")
  end

  defp redirect_to_slug_or_404(conn, slug_or_id) when is_integer(slug_or_id) do
    redirect_to_slug_or_404(conn, Repo.get_by(Dataset, [id: slug_or_id]))
  end

  defp redirect_to_slug_or_404(conn, slug_or_id) do
    redirect_to_slug_or_404(conn, Repo.get_by(Dataset, [datagouv_id: slug_or_id]))
  end

end
