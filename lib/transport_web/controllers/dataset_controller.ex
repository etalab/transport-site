defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Authentication
  alias Transport.Datagouvfr.Client.Datasets
  alias Transport.Datagouvfr.{Authentication, Client}
  alias Transport.ReusableData
  require Logger

  def index(%Plug.Conn{} = conn, params), do: list_datasets(conn, params)

  def list_datasets(%Plug.Conn{} = conn, %{} = params) do
    config = make_pagination_config(params)
    datasets =
        params
        |> case do
          %{"q" => q} -> ReusableData.search_datasets(q, %{:validations => 0})
          _ -> ReusableData.list_datasets(params, %{:validations => 0})
        end
        |> Scrivener.paginate(config)

    conn
    |> assign(:datasets, datasets)
    |> assign(:q, Map.get(params, "q"))
    |> render("index.html")
  end

  def details(%Plug.Conn{} = conn, %{"slug" => slug_or_id}) do
    slug_or_id
    |> ReusableData.get_dataset
    |> case do
      nil -> redirect_to_slug_or_404(conn, slug_or_id)
      dataset ->
        conn
        |> assign(:dataset, dataset)
        |> assign(:discussions, Client.get_discussions(conn, dataset.id))
        |> assign(:community_ressources, Client.get_community_ressources(conn, dataset.id))
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> assign(:is_subscribed, Datasets.current_user_subscribed?(conn, dataset.id))
        |> render("details.html")
    end
  end

  def by_aom(%Plug.Conn{} = conn, %{"commune" => commune}), do: list_datasets(conn, %{commune_principale: commune})
  def by_region(%Plug.Conn{} = conn, %{"region" => region}), do: list_datasets(conn, %{region: region})
  def by_type(%Plug.Conn{} = conn, %{"type" => type}), do: list_datasets(conn, %{type: type})

  defp redirect_to_slug_or_404(conn, slug_or_id) do
    slug_or_id
    |> ReusableData.get_dataset_slug
    |> case do
      nil ->
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "404.html")
      slug -> redirect(conn, to: dataset_path(conn, :details, slug))
    end
  end
end
