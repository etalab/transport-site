defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData
  alias Transport.Datagouvfr.Authentication
  alias Transport.Datagouvfr.Client.{Organizations, Datasets, Resources}
  require Logger

  def index(%Plug.Conn{} = conn, _params) do
    conn
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end

  def new(%Plug.Conn{} = conn, %{"id" => id}) do
    case Organizations.get(conn, id) do
      {:ok, organization} ->
        conn
        |> assign(:organization, organization)
        |> assign(:form_action_function, get_form_action_function(conn))
        |> assign(:linked_dataset_id, get_session(conn, :linked_dataset_id))
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
         {:ok, _resource} <- Resources.upload(conn,
                                              dataset["id"],
                                              params["dataset"])
    do
        redirect(conn, to: user_path(conn, :add_badge_dataset, dataset["id"]))
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

  def create_community_resource(%Plug.Conn{} = conn,
                                %{"organization" => organization} = params) do
    with {:ok, resource} <- Resources.upload_community_resource(
                               conn,
                               params,
                               get_session(conn, :linked_dataset_id)),
         {:ok, _} <- Resources.put_community_resource(
                       conn,
                       params,
                       resource["id"],
                       get_session(conn, :linked_dataset_id))
    do
        conn
        |> put_flash(:info,
                     dgettext("dataset",
                              "Your modified version of this dataset has beed added"))
        |> redirect(to: dataset_path(conn,
                                     :details,
                                     get_session(conn, :linked_dataset_id)))
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
        |> assign(:site, Application.get_env(:oauth2, Authentication)[:site])
        |> render("details.html")
    end
  end

  defp get_form_action_function(conn) do
    if get_session(conn, :linked_dataset_id) == nil do
      :create
    else
      :create_community_resource
    end
  end
end
