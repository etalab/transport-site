defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.{Datasets, Resources, Validation}
  alias DB.{Dataset, Repo, Resource, Validation}
  alias Transport.DataVisualization
  alias Transport.ImportData
  require Logger

  import TransportWeb.ResourceView, only: [issue_type: 1]

  def details(conn, %{"id" => id} = params) do
    config = make_pagination_config(params)

    resource =
      Resource
      |> Repo.get!(id)
      |> Repo.preload([:validation, dataset: [:resources]])

    case Resource.has_metadata?(resource) do
      false ->
        conn |> put_status(:not_found) |> put_view(ErrorView) |> render("404.html")

      true ->
        issues = resource.validation |> Validation.get_issues(params)

        issue_type =
          case params["issue_type"] do
            nil -> issue_type(issues)
            issue_type -> issue_type
          end

        issue_data_vis = resource.validation.data_vis[issue_type]
        has_features = DataVisualization.has_features(issue_data_vis["geojson"])

        encoded_data_vis =
          case {has_features, Jason.encode(issue_data_vis)} do
            {false, _} -> nil
            {true, {:ok, encoded_data_vis}} -> encoded_data_vis
            _ -> nil
          end

        conn
        |> assign(:resource, resource)
        |> assign(:other_resources, Resource.other_resources(resource))
        |> assign(:issues, Scrivener.paginate(issues, config))
        |> assign(:data_vis, encoded_data_vis)
        |> assign(:validation_summary, Validation.summary(resource.validation))
        |> assign(:severities_count, Validation.count_by_severity(resource.validation))
        |> render("details.html")
    end
  end

  def choose_action(conn, _), do: render(conn, "choose_action.html")

  @spec datasets_list(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def datasets_list(conn, _params) do
    conn
    |> assign_or_flash(
      fn -> Dataset.user_datasets(conn) end,
      :datasets,
      "Unable to get resources, please retry."
    )
    |> assign_or_flash(
      fn -> Dataset.user_org_datasets(conn) end,
      :org_datasets,
      "Unable to get resources, please retry."
    )
    |> render("list.html")
  end

  @spec resources_list(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resources_list(conn, %{"dataset_id" => dataset_id}) do
    conn
    |> assign_or_flash(
      fn -> Datasets.get(dataset_id) end,
      :dataset,
      "Unable to get resources, please retry."
    )
    |> render("resources_list.html")
  end

  @spec form(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def form(conn, %{"dataset_id" => dataset_id}) do
    conn
    |> assign_or_flash(
      fn -> Datasets.get(dataset_id) end,
      :dataset,
      "Unable to get resources, please retry."
    )
    |> render("form.html")
  end

  def download(conn, %{"id" => id}) do
    resource = Resource |> Repo.get!(id)

    case HTTPoison.get(resource.url) do
      {:ok, response} ->
        headers = Enum.into(response.headers, %{}, fn {h, v} -> {String.downcase(h), v} end)
        %{"content-type" => content_type} = headers

        send_download(conn, {:binary, response.body},
          content_type: content_type,
          disposition: :attachment,
          filename: resource.url |> Path.basename()
        )

      {:error, _error} ->
        conn |> put_status(:not_found) |> render(ErrorView, "404.html")
    end
  end

  @spec post_file(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_file(conn, params) do
    success_message =
      if Map.has_key?(params, "file") do
        dgettext("resource", "File uploaded!")
      else
        dgettext("resource", "Resource updated with URL!")
      end

    with {:ok, _} <- Resources.update(conn, params),
         dataset when not is_nil(dataset) <-
           Repo.get_by(Dataset, datagouv_id: params["dataset_id"]),
         {:ok, _} <- ImportData.import_dataset_logged(dataset),
         {:ok, _} <- Dataset.validate(dataset) do
      conn
      |> put_flash(:info, success_message)
      |> redirect(to: dataset_path(conn, :details, params["dataset_id"]))
    else
      {:error, error} ->
        Logger.error(
          "Unable to update resource #{params["resource_id"]} of dataset #{params["dataset_id"]}, error: #{inspect(error)}"
        )

        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> form(params)

      nil ->
        Logger.error("Unable to get dataset with datagouv_id: #{params["dataset_id"]}")

        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> form(params)
    end
  end

  defp assign_or_flash(conn, getter, kw, error) do
    case getter.() do
      {:ok, value} ->
        assign(conn, kw, value)

      {:error, _error} ->
        conn
        |> assign(kw, [])
        |> put_flash(:error, Gettext.dgettext(TransportWeb.Gettext, "resource", error))
    end
  end
end
