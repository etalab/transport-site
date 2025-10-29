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
    case load_resource(id) do
      nil ->
        not_found(conn)

      resource ->
        validation = latest_validation(resource, include_result: not prefer_digest?(resource))

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
          |> assign(:validation, validation)
          |> put_resource_flash(resource.dataset.is_active)

        cond do
          Resource.gtfs?(resource) -> render_gtfs_details(conn, params, resource, validation)
          Resource.netex?(resource) -> render_netex_details(conn, params, resource, validation)
          true -> render_details(conn, resource)
        end
    end
  end

  defp prefer_digest?(%Resource{} = resource) do
    Resource.gtfs?(resource) || Resource.netex?(resource)
  end

  defp default_params?(params), do: Map.keys(params) == ["id"]

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

  defp latest_validation(%Resource{id: resource_id} = resource, opts) do
    validators = resource |> Transport.ValidatorsSelection.validators() |> Enum.filter(&(&1 in @enabled_validators))

    validator =
      cond do
        Enum.count(validators) == 1 -> hd(validators)
        Enum.empty?(validators) -> nil
      end

    DB.MultiValidation.resource_latest_validation(resource_id, validator, opts)
  end

  def render_details(conn, resource) do
    conn |> assign(:resource, resource) |> render("details.html")
  end

  defp render_gtfs_details(conn, params, resource, validation) do
    validation_details = {_, _, _, _, issues} = build_gtfs_validation_details(resource, validation, params)

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

  defp build_gtfs_validation_details(_resource, nil, _params), do: {nil, nil, nil, [], []}

  defp build_gtfs_validation_details(
         %DB.Resource{} = resource,
         %{digest: nil, metadata: metadata = %DB.ResourceMetadata{}},
         params
       ) do
    # Notably useful if digest wasn't persisted yet

    %DB.MultiValidation{result: validation_result} = latest_validation(resource, include_result: true)

    %{"summary" => summary, "stats" => stats} =
      Transport.Validators.GTFSTransport.digest(validation_result)

    issues = Transport.Validators.GTFSTransport.get_issues(validation_result, params)

    {summary, stats, metadata.metadata, metadata.modes, issues}
  end

  defp build_gtfs_validation_details(
         %DB.Resource{} = resource,
         %{digest: digest, metadata: metadata = %DB.ResourceMetadata{}},
         params
       ) do
    %{"summary" => summary, "stats" => stats, "issues" => issues} = digest

    issues =
      if default_params?(params) do
        issues
      else
        %DB.MultiValidation{result: validation_result} = latest_validation(resource, include_result: true)

        Transport.Validators.GTFSTransport.get_issues(validation_result, params)
      end

    {summary, stats, metadata.metadata, metadata.modes, issues}
  end

  defp render_netex_details(conn, params, resource, validation) do
    {results_adapter, validation_details, errors_template, max_severity} =
      build_netex_validation_details(resource, validation, params)

    conn
    |> assign_base_resource_details(params, resource, validation_details)
    |> assign(:errors_template, errors_template)
    |> assign(:results_adapter, results_adapter)
    |> assign(:max_severity, max_severity)
    |> assign(:data_vis, nil)
    |> render("netex_details.html")
  end

  defp build_netex_validation_details(_resource, nil, _params), do: {nil, {nil, nil, nil, [], []}, nil, nil}

  defp build_netex_validation_details(
         %DB.Resource{} = resource,
         %{validator_version: version, digest: nil, metadata: metadata = %DB.ResourceMetadata{}},
         params
       ) do
    # Notably useful if digest wasn't persisted yet
    %DB.MultiValidation{result: validation_result} = latest_validation(resource, include_result: true)
    results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
    digest = results_adapter.digest(validation_result)

    build_netex_validation_details(resource, version, digest, metadata, params)
  end

  defp build_netex_validation_details(
         resource,
         %{validator_version: version, digest: digest, metadata: metadata = %DB.ResourceMetadata{}},
         params
       ) do
    build_netex_validation_details(resource, version, digest, metadata, params)
  end

  defp build_netex_validation_details(resource, version, digest, metadata, params) do
    %{"summary" => summary, "stats" => stats, "max_severity" => max_severity} = digest
    results_adapter = Transport.Validators.NeTEx.ResultsAdapter.resolve(version)
    errors_template = pick_netex_errors_template(version)

    issues =
      if default_params?(params) do
        digest["issues"]
      else
        # Digest doesn't include issues for non default params
        %DB.MultiValidation{result: validation_result} = latest_validation(resource, include_result: true)

        results_adapter.get_issues(validation_result, params)
      end

    {results_adapter, {summary, stats, metadata.metadata, metadata.modes, issues}, errors_template, max_severity}
  end

  defp pick_netex_errors_template("0.2.1"), do: "_netex_validation_errors_v0_2_x.html"
  defp pick_netex_errors_template("0.2.0"), do: "_netex_validation_errors_v0_2_x.html"
  defp pick_netex_errors_template(_), do: "_netex_validation_errors_v0_1_0.html"

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
    resource = DB.Resource |> DB.Repo.get!(id) |> DB.Repo.preload(:dataset)

    cond do
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
    resource = DB.Resource |> DB.Repo.get!(id) |> DB.Repo.preload(:dataset)

    cond do
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
            |> put_status(:not_found)
            |> put_view(ErrorView)
            |> render("404.html")
        end
    end
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
