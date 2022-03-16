defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.{Datasets, Resources, Validation}
  alias DB.{Dataset, Repo, Resource, Validation}
  alias Transport.DataVisualization
  alias Transport.ImportData
  require Logger

  import TransportWeb.ResourceView, only: [issue_type: 1]
  import TransportWeb.DatasetView, only: [availability_number_days: 0]

  def details(conn, %{"id" => id} = params) do
    resource =
      Resource
      |> Repo.get!(id)
      |> Repo.preload([:validation, dataset: [:resources]])

    conn =
      conn
      |> assign(:uptime_per_day, DB.ResourceUnavailability.uptime_per_day(resource, availability_number_days()))
      |> assign(:resource_history_infos, DB.ResourceHistory.latest_resource_history_infos(id))
      |> assign(:gtfs_rt_feed, gtfs_rt_feed(conn, resource))
      |> put_resource_flash(resource.dataset.is_active)

    if Resource.is_gtfs?(resource) and Resource.has_metadata?(resource) do
      render_gtfs_details(conn, params, resource)
    else
      conn |> assign(:resource, resource) |> render("details.html")
    end
  end

  defp gtfs_rt_feed(conn, %Resource{} = resource) do
    lang = get_session(conn, :locale)

    Transport.Cache.API.fetch(
      "service_alerts_#{resource.id}_#{lang}",
      fn ->
        if Resource.is_gtfs_rt?(resource) do
          case Transport.GTFSRT.decode_remote_feed(resource.url) do
            {:ok, feed} ->
              %{
                alerts: Transport.GTFSRT.service_alerts_for_display(feed, lang),
                feed: feed
              }

            _ ->
              nil
          end
        else
          nil
        end
      end,
      :timer.minutes(5)
    )
  end

  defp put_resource_flash(conn, false = _dataset_active) do
    conn
    |> put_flash(
      :error,
      dgettext("resource", "This resource belongs to a dataset that has been deleted from data.gouv.fr")
    )
  end

  defp put_resource_flash(conn, _), do: conn

  defp render_gtfs_details(conn, params, resource) do
    config = make_pagination_config(params)
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
    |> assign(:related_files, Resource.get_related_files(resource))
    |> assign(:resource, resource)
    |> assign(:other_resources, Resource.other_resources(resource))
    |> assign(:issues, Scrivener.paginate(issues, config))
    |> assign(:data_vis, encoded_data_vis)
    |> assign(:validation_summary, Validation.summary(resource.validation))
    |> assign(:severities_count, Validation.count_by_severity(resource.validation))
    |> render("gtfs_details.html")
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

  @doc """
  `download` is in charge of downloading resources.

  - If the resource can be "directly downloaded" over HTTPS,
  this method redirects.
  - Otherwise, we proxy the response of the resource's url

  We introduced this method because some browsers
  block downloads of external HTTP resources when
  they are referenced on an HTTPS page.
  """
  def download(conn, %{"id" => id}) do
    resource = Resource |> Repo.get!(id)

    if Resource.can_direct_download?(resource) do
      redirect(conn, external: resource.url)
    else
      case Transport.Shared.Wrapper.HTTPoison.impl().get(resource.url, [], hackney: [follow_redirect: true]) do
        {:ok, %HTTPoison.Response{status_code: 200} = response} ->
          headers = Enum.into(response.headers, %{}, fn {h, v} -> {String.downcase(h), v} end)
          %{"content-type" => content_type} = headers

          send_download(conn, {:binary, response.body},
            content_type: content_type,
            disposition: :attachment,
            filename: Transport.FileDownloads.guess_filename(headers, resource.url)
          )

        _ ->
          conn
          |> put_flash(:error, dgettext("resource", "Resource is not available on remote server"))
          |> put_status(:not_found)
          |> put_view(ErrorView)
          |> render("404.html")
      end
    end
  end

  @spec post_file(Plug.Conn.t(), map) :: Plug.Conn.t()
  def post_file(conn, params) do
    success_message =
      if Map.has_key?(params, "resource_file") do
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
