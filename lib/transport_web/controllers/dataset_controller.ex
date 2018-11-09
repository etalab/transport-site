defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Authentication
  alias Transport.ReusableData
  require Logger

  def index(%Plug.Conn{} = conn, %{"q" => q} = params) when q != "" do
    config = make_pagination_config(params)
    datasets = q |> ReusableData.search_datasets(projection: %{"validations" => 0}) |> Scrivener.paginate(config)

    conn
    |> assign(:datasets, datasets)
    |> assign(:q, q)
    |> render("index.html")
  end

  def index(%Plug.Conn{} = conn, params) do
    config = make_pagination_config(params)
    datasets = ReusableData.list_datasets(projection: %{"validations" => 0}) |> Scrivener.paginate(config)

    conn
    |> assign(:datasets, datasets)
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
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> render("details.html")
    end
  end

  def filtered_datasets(%Plug.Conn{} = conn, %{} = query) do
    config = make_pagination_config(query)
    datasets = query |> ReusableData.list_datasets(projection: %{"validations" => 0}) |> Scrivener.paginate(config)

    conn
    |> assign(:datasets, datasets)
    |> render("index.html")
  end

  def by_aom(%Plug.Conn{} = conn, %{"commune" => commune}), do: filtered_datasets(conn, %{commune_principale: commune})
  def by_region(%Plug.Conn{} = conn, %{"region" => region}), do: filtered_datasets(conn, %{region: region})
  def by_type(%Plug.Conn{} = conn, %{"type" => type}), do: filtered_datasets(conn, %{type: type})
end
