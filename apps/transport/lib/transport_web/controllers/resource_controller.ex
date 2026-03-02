defmodule TransportWeb.ResourceController do
  use TransportWeb, :controller
  alias DB.{Repo, Resource}
  alias Transport.DataVisualization
  import Ecto.Query

  import TransportWeb.ResourceView, only: [latest_validations_nb_days: 0]
  import TransportWeb.DatasetView, only: [availability_number_days: 0]

  def enabled_validators, do: Transport.ValidatorsSelection.validators_for_feature(:resource_controller) |> MapSet.new()

  def details(conn, %{"id" => id} = params) do
    case load_resource(id) do
      nil ->
        not_found(conn)

      resource ->
        resource_history = DB.ResourceHistory.latest_resource_history(id)
        validation = latest_validation(resource, resource_history)

        conn =
          conn
          |> assign(
            :uptime_per_day,
            DB.ResourceUnavailability.uptime_per_day(resource, availability_number_days())
          )
          |> assign(:resource_history, resource_history)
          |> assign(:gtfs_rt_feed, gtfs_rt_feed(conn, resource))
          |> assign(:gtfs_rt_entities, gtfs_rt_entities(resource))
          |> assign(:latest_validations_details, latest_validations_details(resource))
          |> assign(:validation, validation)
          |> put_resource_flash(resource.dataset.is_active)

        cond do
          Resource.gtfs?(resource) and Transport.Validators.GTFSTransport.mine?(validation) ->
            render_gtfs_details(conn, params, resource, validation)

          Resource.netex?(resource) ->
            render_netex_details(conn, params, resource, validation)

          true ->
            render_details(conn, resource)
        end
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> render("404.html")
  end

  defp load_resource(id) do
    Resource
    |> preload([:resources_related, dataset: [:resources, :declarative_spatial_areas]])
    |> Repo.get(id)
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
        DateTime.utc_now() |> DateTime.add(-latest_validations_nb_days(), :day),
        include_result: true
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

  defp latest_validation(%Resource{id: resource_id} = resource, latest_resource_history) do
    # Swap-out the validator for GTFS-Flex
    validators =
      if not is_nil(latest_resource_history) and DB.ResourceHistory.gtfs_flex?(latest_resource_history) do
        [Transport.Validators.MobilityDataGTFSValidator]
      else
        resource |> Transport.ValidatorsSelection.validators() |> Enum.filter(&(&1 in enabled_validators()))
      end

    validator =
      cond do
        Enum.count(validators) == 1 -> hd(validators)
        Enum.empty?(validators) -> nil
      end

    netex? = validator == Transport.Validators.NeTEx.Validator

    DB.MultiValidation.resource_latest_validation(resource_id, validator,
      include_result: not netex?,
      include_binary_result: netex?
    )
  end

  def render_details(conn, resource) do
    conn |> assign(:resource, resource) |> render("details.html")
  end

  defp render_gtfs_details(conn, params, resource, validation) do
    config = make_pagination_config(params)

    {validation_details, issues} = build_gtfs_validation_details(validation, params)

    issue_type =
      case params["issue_type"] do
        nil -> Transport.Validators.GTFSTransport.issue_type(issues)
        issue_type -> issue_type
      end

    conn
    |> assign_base_resource_details(resource, validation_details)
    |> assign(:issues, Scrivener.paginate(issues, config))
    |> assign(:validator, Transport.Validators.GTFSTransport)
    |> assign(:data_vis, encoded_data_vis(issue_type, validation))
    |> render("gtfs_details.html")
  end

  defp build_gtfs_validation_details(nil, _params), do: {{nil, nil, nil, []}, []}

  defp build_gtfs_validation_details(%{result: validation_result, metadata: metadata = %DB.ResourceMetadata{}}, params) do
    summary = Transport.Validators.GTFSTransport.summary(validation_result)
    stats = Transport.Validators.GTFSTransport.count_by_severity(validation_result)
    issues = Transport.Validators.GTFSTransport.get_issues(validation_result, params)

    {{summary, stats, metadata.metadata, metadata.modes}, issues}
  end

  defp render_netex_details(conn, params, resource, validation) do
    config = make_pagination_config(params)

    {results_adapter, validation_details, issues, errors_template, max_severity, xsd_errors} =
      build_netex_validation_details(validation, params)

    {filter, pagination} = issues

    validation_report_url =
      if download_validation_report?(validation, max_severity) do
        DB.Resource.download_validation_report_url(conn, resource)
      end

    conn
    |> assign_base_resource_details(resource, validation_details)
    |> assign(:validation_report_url, validation_report_url)
    |> assign(:filter, filter)
    |> assign(:issues, paginate_netex_results(pagination, config))
    |> assign(:xsd_errors, xsd_errors)
    |> assign(:errors_template, errors_template)
    |> assign(:results_adapter, results_adapter)
    |> assign(:max_severity, max_severity)
    |> assign(:data_vis, nil)
    |> render("netex_details.html")
  end

  defp download_validation_report?(%DB.MultiValidation{binary_result: nil}, _max_severity), do: false
  defp download_validation_report?(_binary_result, %{"max_level" => "NoError"}), do: false
  defp download_validation_report?(_binary_result, _max_severity), do: true

  # For NeTEx results we avoid loading every entries. We emulate
  # Scrivener.paginate based on the total count.
  def paginate_netex_results({total_entries, issues}, config) do
    total_pages = div(total_entries, config.page_size)

    total_pages =
      if rem(total_entries, config.page_size) > 0 do
        total_pages + 1
      else
        total_pages
      end

    %Scrivener.Page{
      entries: issues,
      page_number: config.page_number,
      page_size: config.page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  defp build_netex_validation_details(nil, _params), do: {nil, {nil, nil, nil, []}, {%{}, {0, []}}, nil, nil, []}

  defp build_netex_validation_details(
         %{
           validator_version: version,
           digest: digest,
           binary_result: binary_result,
           metadata: metadata = %DB.ResourceMetadata{}
         },
         params
       ) do
    results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
    summary = digest["summary"]
    stats = digest["stats"]
    errors_template = pick_netex_errors_template(version)
    max_severity = digest["max_severity"]

    pagination_config = make_pagination_config(params)
    issues = results_adapter.get_issues(binary_result, params, pagination_config)
    xsd_errors = results_adapter.summarize_xsd_errors(binary_result)

    {results_adapter, {summary, stats, metadata.metadata, metadata.modes}, issues, errors_template, max_severity,
     xsd_errors}
  end

  defp pick_netex_errors_template("0.2.1"), do: "_netex_validation_errors_v0_2_x.html"
  defp pick_netex_errors_template("0.2.0"), do: "_netex_validation_errors_v0_2_x.html"
  defp pick_netex_errors_template(_), do: "_netex_validation_errors_v0_1_0.html"

  defp assign_base_resource_details(conn, resource, validation_details) do
    {validation_summary, severities_count, metadata, modes} = validation_details

    conn
    |> assign(:related_files, Resource.get_related_files(resource))
    |> assign(:resource, resource)
    |> assign(:other_resources, Resource.other_resources(resource))
    |> assign(:validation_summary, validation_summary)
    |> assign(:severities_count, severities_count)
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
  `download` is in charge of downloading resources OR forwarding and logging requests.

  - If the resource uses a PAN download-link, it logs the request (with a token if specified)
    and redirects to the resource's URL afterward.
  - If the resource can be "directly downloaded" over HTTPS, this method redirects.
  - Otherwise, we proxy the response of the resource's url.

  We introduced this method because some browsers block downloads of external HTTP resources when
  they are referenced on an HTTPS page.
  """
  def download(%Plug.Conn{assigns: %{original_method: "HEAD"}} = conn, %{"id" => id}) do
    resource = get_with_dataset(id)

    cond do
      is_nil(resource) ->
        not_found(conn)

      DB.Dataset.has_custom_tag?(resource.dataset, "authentification_experimentation") ->
        forward_head_response(conn, resource)

      DB.Resource.pan_resource?(resource) ->
        conn |> Plug.Conn.send_resp(:ok, "")

      DB.Resource.can_direct_download?(resource) ->
        conn |> Plug.Conn.send_resp(:not_found, "")

      true ->
        forward_head_response(conn, resource)
    end
  end

  def download(%Plug.Conn{method: "GET"} = conn, %{"id" => id}) do
    resource = get_with_dataset(id)

    cond do
      is_nil(resource) ->
        not_found(conn)

      DB.Dataset.has_custom_tag?(resource.dataset, "authentification_experimentation") ->
        log_and_redirect(conn, resource)

      DB.Resource.pan_resource?(resource) ->
        log_and_redirect(conn, resource)

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
            |> not_found()
        end
    end
  end

  def download_validation_report(%Plug.Conn{method: "GET"} = conn, %{"id" => id}) do
    resource = get_with_dataset(id)

    cond do
      is_nil(resource) ->
        not_found(conn)

      Resource.netex?(resource) ->
        resource_history = DB.ResourceHistory.latest_resource_history(id)
        validation = latest_validation(resource, resource_history)
        download_validation_report(conn, resource, validation)

      true ->
        not_found(conn)
    end
  end

  def download_validation_report(%Plug.Conn{method: "GET"} = conn, resource, %DB.MultiValidation{
        id: mv_id,
        binary_result: binary_result
      })
      when is_binary(binary_result) do
    case binary_result
         |> Transport.Validators.NeTEx.ResultsAdapters.Commons.from_binary()
         |> Explorer.DataFrame.dump_csv() do
      {:ok, validation_report} ->
        DB.FeatureUsage.insert!(
          :download_validation_report,
          get_in(conn.assigns.current_contact.id),
          %{resource_id: resource.id}
        )

        send_download(conn, {:binary, validation_report},
          disposition: :attachment,
          content_type: "text/csv",
          filename: "report-#{resource.id}-#{mv_id}.csv"
        )

      _ ->
        not_found(conn)
    end
  end

  def download_validation_report(%Plug.Conn{method: "GET"} = conn, _, _) do
    not_found(conn)
  end

  defp get_with_dataset(resource_id) do
    DB.Resource
    |> DB.Repo.get(resource_id)
    |> DB.Repo.preload(:dataset)
  end

  defp forward_head_response(%Plug.Conn{} = conn, %DB.Resource{} = resource) do
    case Transport.Shared.Wrapper.HTTPoison.impl().head(resource.url, []) do
      {:ok, %HTTPoison.Response{status_code: status_code, headers: headers}} ->
        send_head_response(conn, status_code, headers)

      _ ->
        conn |> Plug.Conn.send_resp(:bad_gateway, "")
    end
  end

  defp log_and_redirect(%Plug.Conn{} = conn, %DB.Resource{} = resource) do
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
end
