defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias DB.{Repo, Resource}
  alias Transport.DataVisualization
  import Ecto.Query

  import TransportWeb.ResourceView, only: [latest_validations_nb_days: 0]
  import TransportWeb.DatasetView, only: [availability_number_days: 0]

  @enabled_validators MapSet.new([
                        Transport.Validators.GTFSTransport,
                        Transport.Validators.GTFSRT,
                        Transport.Validators.GBFSValidator,
                        Transport.Validators.TableSchema,
                        Transport.Validators.EXJSONSchema,
                        Transport.Validators.NeTEx.Validator
                      ])
  plug(:assign_current_contact when action in [:details])

  def details(conn, %{"id" => id} = params) do
    resource = Resource |> preload([:resources_related, dataset: [:resources]]) |> Repo.get!(id)

    conn =
      conn
      |> assign(
        :uptime_per_day,
        DB.ResourceUnavailability.uptime_per_day(resource, availability_number_days())
      )
      |> assign(:resource_history, DB.ResourceHistory.latest_resource_history(id))
      |> assign(:gtfs_rt_feed, gtfs_rt_feed(conn, resource))
      |> assign(:gtfs_rt_entities, gtfs_rt_entities(resource))
      |> assign(:latest_validations_details, latest_validations_details(resource))
      |> assign(:multi_validation, latest_validation(resource))
      |> put_resource_flash(resource.dataset.is_active)

    cond do
      Resource.gtfs?(resource) -> render_gtfs_details(conn, params, resource)
      Resource.netex?(resource) -> render_netex_details(conn, params, resource)
      true -> render_details(conn, resource)
    end
  end

  def gtfs_rt_entities(%Resource{format: "gtfs-rt", id: id}) do
    recent_limit = Transport.Jobs.GTFSRTMetadataJob.datetime_limit()

    DB.ResourceMetadata
    |> where([rm], rm.resource_id == ^id and rm.inserted_at > ^recent_limit)
    |> select([rm], fragment("DISTINCT(UNNEST(features))"))
    |> DB.Repo.all()
    |> Enum.sort()
  end

  def gtfs_rt_entities(%Resource{}), do: nil

  def latest_validations_details(%Resource{format: "gtfs-rt", id: id}) do
    validations =
      DB.MultiValidation.resource_latest_validations(
        id,
        Transport.Validators.GTFSRT,
        DateTime.utc_now() |> DateTime.add(-latest_validations_nb_days(), :day)
      )

    nb_validations = Enum.count(validations)

    validations
    |> Enum.flat_map(fn %DB.MultiValidation{result: result} -> Map.get(result, "errors", []) end)
    |> Enum.group_by(&Map.fetch!(&1, "error_id"), &Map.take(&1, ["description", "errors_count"]))
    |> Enum.into(%{}, fn {error_id, validations} ->
      {error_id,
       %{
         "description" => validations |> hd() |> Map.get("description"),
         "errors_count" => validations |> Enum.map(& &1["errors_count"]) |> Enum.sum(),
         "occurence" => length(validations),
         "percentage" => (length(validations) / nb_validations * 100) |> round()
       }}
    end)
  end

  def latest_validations_details(%Resource{}), do: nil

  defp gtfs_rt_feed(conn, %Resource{format: "gtfs-rt", url: url, id: id}) do
    lang = get_session(conn, :locale)

    Transport.Cache.fetch(
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

  def render_details(conn, resource) do
    conn |> assign(:resource, resource) |> render("details.html")
  end

  defp render_gtfs_details(conn, params, resource) do
    validation = latest_validation(resource)

    validation_details = {_, _, _, _, issues} = build_gtfs_validation_details(params, resource)

    issue_type =
      case params["issue_type"] do
        nil -> Transport.Validators.GTFSTransport.issue_type(issues)
        issue_type -> issue_type
      end

    conn
    |> assign_base_resource_details(params, resource, validation_details)
    |> assign(:validator, Transport.Validators.GTFSTransport)
    |> assign(:data_vis, encoded_data_vis(issue_type, validation))
    |> render("gtfs_details.html")
  end

  defp build_gtfs_validation_details(params, resource) do
    case latest_validation(resource) do
      %{result: validation_result, metadata: metadata = %DB.ResourceMetadata{}} ->
        summary = Transport.Validators.GTFSTransport.summary(validation_result)
        stats = Transport.Validators.GTFSTransport.count_by_severity(validation_result)
        issues = Transport.Validators.GTFSTransport.get_issues(validation_result, params)

        {summary, stats, metadata.metadata, metadata.modes, issues}

      nil ->
        {nil, nil, nil, [], []}
    end
  end

  defp render_netex_details(conn, params, resource) do
    {results_adapter, validation_details} = build_netex_validation_details(params, resource)

    conn
    |> assign_base_resource_details(params, resource, validation_details)
    |> assign(:results_adapter, results_adapter)
    |> assign(:data_vis, nil)
    |> render("netex_details.html")
  end

  defp build_netex_validation_details(params, resource) do
    case latest_validation(resource) do
      %{validator_version: version, result: validation_result, metadata: metadata = %DB.ResourceMetadata{}} ->
        results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
        summary = results_adapter.summary(validation_result)
        stats = results_adapter.count_by_severity(validation_result)
        issues = results_adapter.get_issues(validation_result, params)

        {results_adapter, {summary, stats, metadata.metadata, metadata.modes, issues}}

      nil ->
        {nil, {nil, nil, nil, [], []}}
    end
  end

  defp assign_base_resource_details(conn, params, resource, validation_details) do
    config = make_pagination_config(params)

    {validation_summary, severities_count, metadata, modes, issues} = validation_details

    conn
    |> assign(:related_files, Resource.get_related_files(resource))
    |> assign(:resource, resource)
    |> assign(:other_resources, Resource.other_resources(resource))
    |> assign(:issues, Scrivener.paginate(issues, config))
    |> assign(:validation_summary, validation_summary)
    |> assign(:severities_count, severities_count)
    |> assign(:validation, latest_validation(resource))
    |> assign(:metadata, metadata)
    |> assign(:modes, modes)
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

  @doc """
  `download` is in charge of downloading resources.

  - If the resource can be "directly downloaded" over HTTPS,
  this method redirects.
  - Otherwise, we proxy the response of the resource's url

  We introduced this method because some browsers
  block downloads of external HTTP resources when
  they are referenced on an HTTPS page.
  """
  def download(%Plug.Conn{assigns: %{original_method: "HEAD"}} = conn, %{"id" => id}) do
    resource = DB.Resource |> DB.Repo.get!(id) |> DB.Repo.preload(:dataset)

    cond do
      DB.Resource.pan_resource?(resource) ->
        conn |> Plug.Conn.send_resp(:ok, "")

      DB.Resource.can_direct_download?(resource) ->
        conn |> Plug.Conn.send_resp(:not_found, "")

      true ->
        case Transport.Shared.Wrapper.HTTPoison.impl().head(resource.url, []) do
          {:ok, %HTTPoison.Response{status_code: status_code, headers: headers}} ->
            send_head_response(conn, status_code, headers)

          _ ->
            conn |> Plug.Conn.send_resp(:bad_gateway, "")
        end
    end
  end

  def download(%Plug.Conn{method: "GET"} = conn, %{"id" => id}) do
    resource = DB.Resource |> DB.Repo.get!(id) |> DB.Repo.preload(:dataset)

    cond do
      DB.Resource.pan_resource?(resource) ->
        download_pan_resource(conn, resource)

      DB.Resource.can_direct_download?(resource) ->
        redirect(conn, external: resource.url)

      true ->
        case Transport.Shared.Wrapper.HTTPoison.impl().get(resource.url, [], hackney: [follow_redirect: true]) do
          {:ok, %HTTPoison.Response{status_code: 200} = response} ->
            headers = Enum.into(response.headers, %{}, &downcase_header(&1))
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

  defp download_pan_resource(%Plug.Conn{} = conn, %DB.Resource{} = resource) do
    case find_token(Map.get(conn.query_params, "token")) do
      {:ok, token} ->
        log_download_request(resource, token)
        redirect(conn, external: resource.latest_url)

      :error ->
        conn |> Plug.Conn.send_resp(:unauthorized, "You must set a valid Authorization header")
    end
  end

  defp log_download_request(%DB.Resource{id: resource_id}, token) do
    token_id =
      case token do
        %DB.Token{id: token_id} -> token_id
        nil -> nil
      end

    %DB.ResourceDownload{}
    |> Ecto.Changeset.change(%{
      time: DateTime.utc_now(),
      resource_id: resource_id,
      token_id: token_id
    })
    |> DB.Repo.insert!()
  end

  defp find_token(nil), do: {:ok, nil}

  defp find_token(secret_hash) do
    case DB.Repo.get_by(DB.Token, secret_hash: secret_hash) do
      %DB.Token{} = token -> {:ok, token}
      nil -> :error
    end
  end

  defp send_head_response(%Plug.Conn{} = conn, status_code, headers) do
    resp_headers =
      headers
      |> Enum.map(&downcase_header/1)
      |> Enum.filter(fn {h, _v} -> Enum.member?(Shared.Proxy.forwarded_headers_allowlist(), h) end)

    conn |> Plug.Conn.merge_resp_headers(resp_headers) |> Plug.Conn.send_resp(status_code, "")
  end

  defp downcase_header({h, v}), do: {String.downcase(h), v}

  defp assign_current_contact(%Plug.Conn{assigns: %{current_user: current_user}} = conn, _options) do
    current_contact =
      if is_nil(current_user) do
        nil
      else
        DB.Contact
        |> DB.Repo.get_by!(datagouv_user_id: Map.fetch!(current_user, "id"))
        |> DB.Repo.preload(:default_tokens)
      end

    assign(conn, :current_contact, current_contact)
  end
end
