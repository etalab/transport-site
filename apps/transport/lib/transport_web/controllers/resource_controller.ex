defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.{Datasets, Resources, User, Validation}
  alias DB.{Dataset, Repo, Resource, Validation}
  alias Transport.ImportData
  import Ecto.Query, only: [from: 2]
  require Logger

  def details(conn, %{"id" => id} = params) do
    config = make_pagination_config(params)

    Resource
    |> Repo.get(id)
    |> Repo.preload([:dataset, :validation])
    |> case do
      nil -> render(conn, "404.html")
      resource ->
        conn
        |> assign(:resource, resource)
        |> assign(:other_resources, Resource.other_resources(resource))
        |> assign(:issues, resource.validation |> Validation.get_issues(params) |> Scrivener.paginate(config))
        |> assign(:validation_summary, Validation.summary(resource.validation))
        |> render("details.html")
    end
  end


  def choose_action(conn, _), do: render conn, "choose_action.html"

  @spec datasets_list(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def datasets_list(conn, _params) do
    conn
    |> assign_or_flash(fn -> Dataset.user_datasets(conn) end, :datasets, "Unable to get resources, please retry.")
    |> assign_or_flash(fn -> Dataset.user_org_datasets(conn) end, :org_datasets, "Unable to get resources, please retry.")
    |> render("list.html")
  end

  @spec resources_list(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resources_list(conn, %{"dataset_id" => dataset_id}) do
    conn
    |> assign_or_flash(fn -> Datasets.get(dataset_id) end, :dataset, "Unable to get resources, please retry.")
    |> render("resources_list.html")
  end

  @spec choose_file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def choose_file(conn, %{"dataset_id" => dataset_id, "resource_id" => resource_id}) do
    conn
    |> assign_or_flash(fn -> Datasets.get(dataset_id) end, :dataset, "Unable to get resources, please retry.")
    |> assign(:action_path, resource_path(conn, :post_file, dataset_id, resource_id))
    |> render("choose_file.html")
  end

  def post_file(conn, params) do
    success_message =
      if Map.has_key?(params, "file") do
        dgettext("resource", "File uploaded!")
      else
        dgettext("resource", "Resource updated with URL!")
      end

    with {:ok, _} <- Resources.update(conn, params["dataset_id"], params["resource_id"], params),
         dataset when not is_nil(dataset) <- Repo.get_by(Dataset, datagouv_id: params["dataset_id"]),
         {:ok, _} <- ImportData.call(dataset) do
        conn
        |> put_flash(:info, success_message)
        |> redirect(to: dataset_path(conn, :details, params["dataset_id"]))
    else
      {:error, error} ->
        Logger.error("Unable to update resource #{params["resource_id"]} of dataset #{params["dataset_id"]}, error: #{inspect(error)}")
        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> assign(:action_path, resource_path(conn, :post_file, params["dataset_id"], params["resource_id"]))
        |> render("choose_file.html")
      nil ->
        Logger.error("Unable to get dataset with datagouv_id: #{params["dataset_id"]}")
        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> assign(:action_path, resource_path(conn, :post_file, params["dataset_id"], params["resource_id"]))
        |> render("choose_file.html")
    end
  end

  defp assign_or_flash(conn, getter, kw, error) do
    case getter.() do
      {:ok, value} -> assign(conn, kw, value)
      {:error, _error} ->
         conn
         |> assign(kw, [])
         |> put_flash(:error, Gettext.dgettext(TransportWeb.Gettext, "resource", error))
    end
  end

end
