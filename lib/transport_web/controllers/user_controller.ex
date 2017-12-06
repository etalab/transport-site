defmodule TransportWeb.UserController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client.{Organizations, User, Datasets}
  alias Transport.DataValidator.Server
  require Logger

  def organizations(%Plug.Conn{} = conn, params) do
    with {:ok, linked_dataset_id} <- get_linked_dataset_id(conn, params),
         conn <- put_session(
                   conn,
                   :linked_dataset_slug,
                   Map.get(params, :linked_dataset_slug)),
         conn <- put_session(conn, :linked_dataset_id, linked_dataset_id),
         {:ok, %{"organizations" => organizations}} <- User.me(conn)
    do
      case organizations do
        [] ->
           redirect(conn, to: user_path(conn, :organization_form))
        _  ->
          conn
          |> assign(:organizations, organizations)
          |> render("organizations.html")
      end
    else
     {:error, error} ->
       Logger.error(error)
       conn
       |> put_status(:internal_server_error)
       |> render(ErrorView, "500.html")
    end
  end

  def organization_form(conn, _params) do
    render conn, "organization_form.html"
  end

  def organization_create(conn, params) do
    conn
    |> Organizations.post(params)
    |> case do
      {:ok, response} ->
        conn
        |> put_flash(:info, dgettext("user", "Organization added"))
        |> redirect(to: user_path(conn, :organization_datasets, response["slug"]))
      {:error, error} ->
        Logger.error(error)
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
      {:validation_error, errors} ->
        conn
        |> put_flash(:errors, errors)
        |> redirect(to: user_path(conn, :organization_form))
    end
  end

  def organization_datasets(conn, %{"slug" => slug}) do
    conn
    |> Organizations.get(slug, :with_datasets)
    |> case do
      {:ok, %{"datasets" => []}} ->
        redirect(conn, to: dataset_path(conn, :new, slug))
      {:ok, response} ->
        conn
        |> get_session(:linked_dataset_id)
        |> case do
          nil ->
            conn
            |> assign(:has_datasets, Enum.empty?(response["datasets"]) == false)
            |> assign(:datasets, response["datasets"])
            |> assign(:organization, response)
            |> render("organization_datasets.html")
          _ ->
            redirect(conn, to: dataset_path(conn, :new, slug))
        end
     {:error, error} ->
       Logger.error(error)
       conn
       |> put_status(:internal_server_error)
       |> render(ErrorView, "500.html")
     end
  end

  def add_badge_dataset(conn, %{"slug" => slug}) do
    conn
    |> Datasets.put(slug, {:add_tag, "GTFS"})
    |> case do
      {:ok, dataset} ->
        Server.validate_data(List.first(dataset["resources"])["url"])
        conn
        |> render("add_badge_dataset.html")
      {:error, error} ->
        Logger.error(error)
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
     end
  end

  defp get_linked_dataset_id(conn, params) do
    case Map.get(params, "linked_dataset_slug") do
      nil -> {:ok, nil}
      dataset_slug ->
        case Datasets.get(conn, dataset_slug) do
          {:ok, dataset} -> {:ok, dataset["id"]}
          {:error, error} -> {:error, error}
        end
    end
  end
end
