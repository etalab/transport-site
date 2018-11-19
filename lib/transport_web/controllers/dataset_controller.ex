defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
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

  def details(%Plug.Conn{} = conn, %{"slug" => slug}) do
    slug
    |> ReusableData.get_dataset
    |> case do
      nil ->
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
      dataset ->
        conn
        |> assign(:dataset, dataset)
        |> assign(:discussions, Client.get_discussions(conn, dataset.id))
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> render("details.html")
    end
  end

  def by_aom(%Plug.Conn{} = conn, %{"commune" => commune}), do: list_datasets(conn, %{commune_principale: commune})
  def by_region(%Plug.Conn{} = conn, %{"region" => region}), do: list_datasets(conn, %{region: region})
  def by_type(%Plug.Conn{} = conn, %{"type" => type}), do: list_datasets(conn, %{type: type})
end
