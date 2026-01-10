defmodule TransportWeb.Backoffice.ProxyConfigLive do
  @moduledoc """
  A view able to display the current running configuration of the proxy.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  alias Transport.Telemetry
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers

  # The number of past days we want to report on (as a positive integer).
  # This is a DRYed ref we are using in multiple places.
  @stats_days 7

  # Authentication is assumed to happen in regular HTTP land. Here we verify
  # the user presence + belonging to admin team, or redirect immediately.
  @impl true
  def mount(params, %{"current_user" => current_user, "csp_nonce_value" => nonce} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket
       |> assign(nonce: nonce, search: params["search"], type: params["type"], disk: params["disk"])
       |> init_state()
       |> update_data()
     end)}
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  defp init_state(socket) do
    socket |> assign(%{search: "", type: ""})
  end

  defp update_data(socket) do
    config = get_proxy_configuration(Transport.Proxy.base_url(socket), @stats_days)

    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      stats_days: @stats_days,
      proxy_configuration: config,
      select_options: Enum.map(config, &{&1.type, &1.type}) |> Enum.uniq() |> Enum.sort()
    )
    |> filter_config()
  end

  @impl true
  def handle_event("change", %{"search" => search, "type" => type, "disk" => disk}, %Phoenix.LiveView.Socket{} = socket) do
    {:noreply,
     socket |> push_patch(to: backoffice_live_path(socket, __MODULE__, search: search, type: type, disk: disk))}
  end

  @impl true
  def handle_event("refresh_proxy_config", _value, socket) do
    config_module().clear_config_cache!()
    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"search" => _, "type" => _, "disk" => _} = params, _uri, socket) do
    {:noreply, filter_config(socket, params)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, update_data(socket)}
  end

  @impl true
  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  def filter_config(%Phoenix.LiveView.Socket{} = socket, %{"search" => search} = params) do
    type = Map.get(params, "type", "")
    disk = Map.get(params, "disk", false)
    socket |> assign(%{search: search, type: type, disk: disk}) |> filter_config()
  end

  defp filter_config(
         %Phoenix.LiveView.Socket{
           assigns: %{proxy_configuration: proxy_configuration, search: search, type: type, disk: disk}
         } =
           socket
       ) do
    filtered_proxy_configuration =
      proxy_configuration |> filter_by_type(type) |> filter_by_search(search) |> filter_by_disk(disk)

    socket |> assign(%{filtered_proxy_configuration: filtered_proxy_configuration})
  end

  defp filter_by_type(config, ""), do: config

  defp filter_by_type(config, value),
    do: Enum.filter(config, fn %{type: type} -> type == value end)

  defp filter_by_search(config, ""), do: config

  defp filter_by_search(config, value) do
    Enum.filter(config, fn %{unique_slug: unique_slug} ->
      String.contains?(normalize(unique_slug), normalize(value))
    end)
  end

  defp filter_by_disk(config, "true") do
    Enum.filter(config, fn map -> Map.get(map, :caching, false) == "disk" end)
  end

  defp filter_by_disk(config, _), do: config

  @doc """
  iex> normalize("Paris")
  "paris"
  iex> normalize("vélo")
  "velo"
  iex> normalize("Châteauroux")
  "chateauroux"
  """
  def normalize(value) do
    value |> String.normalize(:nfd) |> String.replace(~r/[^A-z]/u, "") |> String.downcase()
  end

  defp config_module, do: Application.fetch_env!(:transport, :unlock_config_fetcher)

  @doc """
  Builds a list of maps containing what we need on display on screen, based on configuration
  plus a bit of cache state and statistics.
  """
  def get_proxy_configuration(proxy_base_url, stats_days) do
    # NOTE: if the stats query becomes too costly, we will be able to throttle it every N seconds instead,
    # using a simple cache. At the moment, `get_proxy_configuration` is called once per frame, and not
    # once per item.
    stats = DB.Metrics.for_last_days(stats_days, event_names())

    config_module().fetch_config!()
    |> Map.values()
    |> Enum.sort_by(& &1.identifier)
    |> Enum.map(fn resource ->
      proxy_base_url
      |> extract_config(resource)
      |> add_cache_state()
      |> add_stats(stats)
    end)
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.Generic.HTTP{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier),
      original_url: resource.target_url,
      ttl: resource.ttl,
      type: "HTTP",
      caching: resource.caching
    }
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.SIRI{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier),
      original_url: resource.target_url,
      ttl: nil,
      type: "SIRI"
    }
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.Aggregate{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier),
      original_url: nil,
      # At time of writing, the global feed is not cached
      ttl: "N/A",
      # We do not display the internal count for aggregate item at the moment
      internal_count_default_value: nil,
      type: "Aggregate"
    }
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.S3{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier),
      # TODO: display original bucket & path name
      original_url: nil,
      ttl: resource.ttl,
      type: "S3"
    }
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.GBFS{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier) <> "/gbfs.json",
      original_url: resource.base_url,
      ttl: resource.ttl,
      type: "GBFS"
    }
  end

  defp event_names do
    Telemetry.proxy_request_event_names() |> Enum.map(&Telemetry.database_event_name/1)
  end

  # a bit over the top, but this allows to keep events & database strings definitions in the telemetry module
  defp db_filter_for_event(type) do
    type
    |> Telemetry.proxy_request_event_name()
    |> Telemetry.database_event_name()
  end

  defp add_stats(item, stats) do
    metrics_target = Unlock.Telemetry.target_for_identifier(item.unique_slug)
    counts = stats[metrics_target] || %{}

    Map.merge(item, %{
      stats_external_requests: Map.get(counts, db_filter_for_event(:external), 0),
      stats_internal_requests:
        Map.get(counts, db_filter_for_event(:internal), Map.get(item, :internal_count_default_value, 0))
    })
  end

  defp add_cache_state(%{caching: "disk"} = item) do
    cache_key = item.unique_slug |> Unlock.Shared.cache_key()
    cache_entry = cache_key |> Unlock.Shared.cache_entry()

    if cache_entry do
      Map.merge(item, %{
        cache_size: (File.stat!(cache_entry.body).size |> Sizeable.filesize()) <> " sur disque",
        cache_status: cache_entry.status,
        cache_ttl: cache_ttl(cache_key)
      })
    else
      item
    end
  end

  defp add_cache_state(item) do
    cache_key = item.unique_slug |> Unlock.Shared.cache_key()
    cache_entry = cache_key |> Unlock.Shared.cache_entry()

    if cache_entry do
      Map.merge(item, %{
        cache_size: cache_entry.body |> byte_size() |> Sizeable.filesize(),
        cache_status: cache_entry.status,
        cache_ttl: cache_ttl(cache_key)
      })
    else
      item
    end
  end

  defp cache_ttl(cache_key) do
    case Unlock.Shared.cache_ttl(cache_key) do
      {:ok, nil} ->
        "no ttl"

      {:ok, res_in_ms} ->
        in_seconds = res_in_ms / 1000
        "#{in_seconds |> Float.round() |> trunc() |> Helpers.format_number()}s"
    end
  end
end
