defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.{Datasets, Resources}
  alias DB.{Dataset, Repo, Resource}
  alias Transport.DataVisualization
  alias Transport.ImportData
  require Logger
  import Ecto.Query

  import TransportWeb.ResourceView, only: [issue_type: 1]
  import TransportWeb.DatasetView, only: [availability_number_days: 0]

  @enabled_validators MapSet.new([
                        Transport.Validators.GTFSTransport,
                        Transport.Validators.GTFSRT,
                        Transport.Validators.GBFSValidator,
                        Transport.Validators.TableSchema,
                        Transport.Validators.EXJSONSchema
                      ])

  def details(conn, %{"id" => id} = params) do
    resource = Resource |> Repo.get!(id) |> Repo.preload(dataset: [:resources])

    conn =
      conn
      |> assign(
        :uptime_per_day,
        DB.ResourceUnavailability.uptime_per_day(resource, availability_number_days())
      )
      |> assign(:resource_history_infos, DB.ResourceHistory.latest_resource_history_infos(id))
      |> assign(:gtfs_rt_feed, gtfs_rt_feed(conn, resource))
      |> assign(:gtfs_rt_entities, gtfs_rt_entities(resource))
      |> assign(:multi_validation, latest_validation(resource))
      |> put_resource_flash(resource.dataset.is_active)

    if Resource.is_gtfs?(resource) do
      render_gtfs_details(conn, params, resource)
    else
      conn |> assign(:resource, resource) |> render("details.html")
    end
  end

  def gtfs_rt_entities(%Resource{format: "gtfs-rt", id: id}) do
    recent_limit = Transport.Jobs.GTFSRTEntitiesJob.datetime_limit()

    DB.ResourceMetadata
    |> where([rm], rm.resource_id == ^id and rm.inserted_at > ^recent_limit)
    |> select([rm], fragment("DISTINCT(UNNEST(features))"))
    |> DB.Repo.all()
    |> Enum.sort()
  end

  def gtfs_rt_entities(%Resource{}), do: nil

  defp gtfs_rt_feed(conn, %Resource{format: "gtfs-rt", url: url, id: id}) do
    lang = get_session(conn, :locale)

    Transport.Cache.API.fetch(
      "gtfs_rt_feed_#{id}_#{lang}",
      fn ->
        case Transport.GTFSRT.decode_remote_feed(url) do
          {:ok, feed} ->
            %{
              alerts: Transport.GTFSRT.service_alerts_for_display(feed, lang),
              feed_is_too_old: Transport.GTFSRT.feed_is_too_old?(feed),
              feed_timestamp_delay: Transport.GTFSRT.feed_timestamp_delay(feed),
              feed: feed
            }

          {:error, _} ->
            :error
        end
      end,
      :timer.minutes(5)
    )
  end

  defp gtfs_rt_feed(_conn, %Resource{}), do: nil

  defp put_resource_flash(conn, false = _dataset_active) do
    conn
    |> put_flash(
      :error,
      dgettext(
        "resource",
        "This resource belongs to a dataset that has been deleted from data.gouv.fr"
      )
    )
  end

  defp put_resource_flash(conn, _), do: conn

  defp latest_validation(%Resource{id: resource_id} = resource) do
    validators = resource |> Transport.ValidatorsSelection.validators() |> Enum.filter(&(&1 in @enabled_validators))

    validator =
      cond do
        Enum.count(validators) == 1 -> hd(validators)
        Enum.empty?(validators) -> nil
      end

    DB.MultiValidation.resource_latest_validation(resource_id, validator)
  end

  defp render_gtfs_details(conn, params, resource) do
    config = make_pagination_config(params)

    validation = resource |> latest_validation()

    {validation_summary, severities_count, metadata, modes, issues} =
      case validation do
        %{result: validation_result, metadata: %DB.ResourceMetadata{metadata: metadata, modes: modes}} ->
          {Transport.Validators.GTFSTransport.summary(validation_result),
           Transport.Validators.GTFSTransport.count_by_severity(validation_result), metadata, modes,
           Transport.Validators.GTFSTransport.get_issues(validation_result, params)}

        nil ->
          {nil, nil, nil, [], []}
      end

    issue_type =
      case params["issue_type"] do
        nil -> issue_type(issues)
        issue_type -> issue_type
      end

    conn
    |> assign(:related_files, Resource.get_related_files(resource))
    |> assign(:resource, resource)
    |> assign(:other_resources, Resource.other_resources(resource))
    |> assign(:issues, Scrivener.paginate(issues, config))
    |> assign(:data_vis, encoded_data_vis(issue_type, validation))
    |> assign(:validation_summary, validation_summary)
    |> assign(:severities_count, severities_count)
    |> assign(:validation, validation)
    |> assign(:metadata, metadata)
    |> assign(:modes, modes)
    |> render("gtfs_details.html")
  end

  def encoded_data_vis(_, nil), do: nil

  def encoded_data_vis(issue_type, validation) do
    issue_data_vis = validation.data_vis[issue_type]
    has_features = DataVisualization.has_features(issue_data_vis["geojson"])

    case {has_features, Jason.encode(issue_data_vis)} do
      {false, _} -> nil
      {true, {:ok, encoded_data_vis}} -> encoded_data_vis
      _ -> nil
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

  def proxy_requests_stats_nb_days, do: 15

  @spec proxy_statistics(Plug.Conn.t(), map) :: Plug.Conn.t()
  def proxy_statistics(conn, _params) do
    datasets =
      [
        Dataset.user_datasets(conn),
        Dataset.user_org_datasets(conn)
      ]
      |> Enum.filter(&(elem(&1, 0) == :ok))
      |> Enum.flat_map(&elem(&1, 1))

    proxy_stats =
      datasets
      |> Enum.flat_map(& &1.resources)
      |> Enum.filter(&DB.Resource.served_by_proxy?/1)
      # Gotcha: this is a N+1 problem. Okay as long as a single producer
      # does not have a lot of feeds/there is not a lot of traffic on this page
      |> Enum.into(%{}, fn %DB.Resource{id: id} = resource ->
        {id, DB.Metrics.requests_over_last_days(resource, proxy_requests_stats_nb_days())}
      end)

    conn
    |> assign(:datasets, datasets)
    |> assign(:proxy_stats, proxy_stats)
    |> assign(:proxy_requests_stats_nb_days, proxy_requests_stats_nb_days())
    |> render("proxy_statistics.html")
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
