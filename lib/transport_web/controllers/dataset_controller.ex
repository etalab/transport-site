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
    |> assign(:order_by, params["order_by"])
    |> render_or_redirect(params)
  end

  defp render_or_redirect(%Plug.Conn{assigns: %{datasets: %{total_entries: 1}}} = conn, _params) do
    entries = conn.assigns[:datasets].entries

    conn
    |> redirect(to: dataset_path(conn, :details, List.first(entries).slug))
  end
  defp render_or_redirect(conn, params) do
    conn
    |> assign(:q, Map.get(params, "q"))
    |> render("index.html")
  end

  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    Dataset
    |> where([slug: ^slug_or_id])
    |> Dataset.preload_without_validations
    |> Repo.one()
    |> case do
      nil -> redirect_to_slug_or_404(conn, slug_or_id)
      dataset ->
        conn
        |> assign(:dataset, dataset)
        |> assign(:count_validations, Dataset.count_validations(dataset))
        |> assign(:discussions, Client.get_discussions(conn, dataset.datagouv_id))
        |> assign(:community_ressources, Client.get_community_ressources(conn, dataset.datagouv_id))
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> assign(:is_subscribed, Datasets.current_user_subscribed?(conn, dataset.datagouv_id))
        |> render("details.html")
    end
  end

  def by_aom(%Plug.Conn{} = conn, %{"commune" => _} = params), do: list_datasets(conn, params)
  def by_region(%Plug.Conn{} = conn, %{"region" => _} = params), do: list_datasets(conn, params)
  def by_type(%Plug.Conn{} = conn, %{"type" => _} = params), do: list_datasets(conn, params)

  defp get_datasets(params) do
    config = make_pagination_config(params)
    select = [:id, :description, :licence, :logo, :spatial, :title, :slug]

    params
    |> Dataset.list_datasets(select)
    |> Repo.paginate(page: config.page_number)
  end

  defp get_regions(params) do
    sub = params
    |> Dataset.list_datasets([])
    |> exclude(:preload)
    |> exclude(:select)
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
