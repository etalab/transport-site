defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.{Datasets, Resources, User, Validation}
  alias Transport.{Dataset, Repo, Resource, Validation}
  import Ecto.Query, only: [from: 2]

  def details(conn, params) do
    config = make_pagination_config(params)
    id = params["id"]

    case Repo.get(Resource, id) do
      nil -> render(conn, "404.html")
      resource ->
        resource_with_dataset = resource |> Repo.preload([:dataset, :validation])

        other_resources_query = from r in Resource,
          where: r.dataset_id == ^resource.dataset_id and r.id != ^resource.id and not is_nil(r.metadata)

        current_issues = get_issues(resource_with_dataset.validation, params)

        render(
          conn,
          "details.html",
          %{resource: resource_with_dataset,
           other_resources: Repo.all(other_resources_query),
           issues: Scrivener.paginate(current_issues, config),
           validation_summary: validation_summary(resource_with_dataset.validation)
          }
        )
    end
  end

  defp get_issues(%{details: nil}, _), do: []
  defp get_issues(%{details: validations}, %{"issue_type" => issue_type}), do: Map.get(validations, issue_type,  [])
  defp get_issues(%{details: validations}, _) do
    validations
    |> Map.values
    |> List.first
  end

  defp validation_summary(%{details: issues}) do
    existing_issues = issues
    |> Enum.map(fn {key, issues} -> {key, %{
      count: Enum.count(issues),
      title: Resource.issues_short_translation()[key],
      severity: issues |> List.first |> Map.get("severity")
    }} end)
    |> Map.new

    Resource.issues_short_translation
    |> Enum.map(fn {key, title} -> {key, %{count: 0, title: title, severity: "Irrelevant"} }end)
    |> Map.new
    |> Map.merge(existing_issues)
    |> Enum.group_by(fn {_, issue} -> issue.severity end)
    |> Enum.sort_by(fn {severity, _} -> Validation.severities(severity).level end)
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

end
