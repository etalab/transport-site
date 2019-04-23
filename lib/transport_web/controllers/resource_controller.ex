defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.{Datasets, Resources, User}
  alias Transport.{Dataset, Repo, Resource, Validation}

  def details(conn, params) do
    config = make_pagination_config(params)
    id = params["id"]

    case Repo.get(Resource, id) do
      nil -> render(conn, "404.html")
      resource ->
        resource_with_dataset = resource |> Repo.preload([:dataset, :validation])
        dataset = resource_with_dataset.dataset |> Repo.preload([:resources])
        other_resources =
          dataset.resources
          |> Stream.reject(&(Integer.to_string(&1.id) == id))
          |> Stream.filter(&Resource.valid?/1)
          |> Enum.to_list()

        issue_type = get_issue_type(params, resource_with_dataset.validation)
        issues = get_issues(resource_with_dataset.validation, issue_type, config)

        issue_types = for it <- Resource.issue_types,
          into: %{},
          do: {it, count_issues(resource_with_dataset.validation, it)}

        render(
          conn,
          "details.html",
          %{resource: resource_with_dataset,
           other_resources: other_resources,
           dataset: dataset,
           issue_types: issue_types,
           issue_type: issue_type,
           issues: issues}
        )
    end
  end

  def choose_action(conn, _), do: render conn, "choose_action.html"

  @spec datasets_list(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def datasets_list(conn, _params) do
    filter = fn d -> Repo.get_by(Dataset, datagouv_id: d["id"]) end

    conn = conn
    |> assign_or_flash(&User.datasets/1, :datasets, "Unable to get resources, please retry.")
    |> assign_or_flash(&User.org_datasets/1, :org_datasets, "Unable to get resources, please retry.")

    conn
    |> assign(:datasets, Enum.filter(conn.assigns.datasets, filter))
    |> assign(:org_datasets, Enum.filter(conn.assigns.org_datasets, filter))
    |> render("list.html")
  end

  @spec resources_list(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def resources_list(conn, %{"dataset_id" => dataset_id}) do
    conn
    |> assign_or_flash(fn conn -> Datasets.get(conn, dataset_id) end, :dataset, "Unable to get resources, please retry.")
    |> render("resources_list.html")
  end

  @spec choose_file(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def choose_file(conn, %{"dataset_id" => dataset_id, "resource_id" => resource_id}) do
    conn
    |> assign_or_flash(fn conn -> Datasets.get(conn, dataset_id) end, :dataset, "Unable to get resources, please retry.")
    |> assign(:action_path, resource_path(conn, :post_file, dataset_id, resource_id))
    |> render("choose_file.html")
  end

  def post_file(conn, params) do
    case Resources.upload(conn, params["dataset_id"], params["resource_id"], params["resource_file"]) do
      {:ok, _} ->
        conn
        |> put_flash(:info, dgettext("resource", "File uploaded!"))
        |> redirect(to: dataset_path(conn, :details, params["dataset_id"]))
      {:error, _error} ->
        conn
        |> put_flash(:error, dgettext("resource", "Unable to upload file"))
        |> assign(:action_path, resource_path(conn, :post_file, params["dataset_id"], params["resource_id"]))
        |> render("choose_file.html")
    end
  end

  defp assign_or_flash(conn, getter, kw, error) do
    case getter.(conn) do
      {:ok, value} -> assign(conn, kw, value)
      {:error, _error} ->
         conn
         |> assign(kw, [])
         |> put_flash(:error, Gettext.dgettext(TransportWeb.Gettext, "resource", error))
    end
  end

  defp get_issue_type(%{"issue_type" => issue_type}, _), do: issue_type
  defp get_issue_type(_, %Validation{details: validations}) when validations != nil and validations != %{} do
    {issue_type, _issues} = validations |> Map.to_list() |> List.first()
    issue_type
  end
  defp get_issue_type(_, _), do: nil

  defp get_issues(%{details: validations}, issue_type, config) when validations != nil do
    validations
    |> Map.get(issue_type,  [])
    |> Scrivener.paginate(config)
  end
  defp get_issues(_, _, _), do: []

  defp count_issues(%{details: validations}, issue_type) when validations != nil do
    validations
    |> Map.get(issue_type, [])
    |> Enum.count
  end
  defp count_issues(_, _), do: 0
end
