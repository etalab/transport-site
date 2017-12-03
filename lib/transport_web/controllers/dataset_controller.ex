defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData
  alias Transport.Datagouvfr.Authentication
  alias Transport.Datagouvfr.Client.{Organizations, Datasets}
  require Logger

  def index(%Plug.Conn{} = conn, _params) do
    conn
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end

  def new(%Plug.Conn{} = conn, %{"slug" => slug}) do
    case Organizations.get(conn, slug) do
      {:ok, organization} ->
        conn
        |> assign(:organization, organization)
        |> render("form.html")
      {:error, error}     ->
        Logger.error(error)
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
    end
  end

  def create(%Plug.Conn{} = conn, %{"organization" => organization} = params) do
    with {:ok, dataset}  <- Datasets.post(conn, params),
         {:ok, _resource} <- Datasets.upload_resource(conn,
                                              dataset["id"],
                                              params["dataset"]) do
        redirect(conn, to: user_path(conn, :add_badge_dataset, dataset["slug"]))
    else
      {:validation_error, errors} ->
        conn
        |> put_flash(:errors, Enum.map(errors, fn({_, _, _, s}) -> s end))
        |> redirect(to: dataset_path(conn, :new, organization))
      {:error, error} ->
        Logger.error(error)
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
    end
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
        |> assign(:dataset_id, ReusableData.get_dataset_id(conn, dataset))
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> render("details.html")
    end
  end
end
