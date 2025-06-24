defmodule TransportWeb.Backoffice.ProxyConfigLive do
  @moduledoc """
  A view able to display the current running configuration of the proxy.
  """
  use Phoenix.LiveView
  alias Transport.Telemetry
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.Router.Helpers

  # The number of past days we want to report on (as a positive integer).
  # This is a DRYed ref we are using in multiple places.
  @stats_days 7

  # Authentication is assumed to happen in regular HTTP land. Here we verify
  # the user presence + belonging to admin team, or redirect immediately.
  def mount(_params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()
       socket |> update_data()
     end)}
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      stats_days: @stats_days,
      proxy_configuration: get_proxy_configuration(Transport.Proxy.base_url(socket), @stats_days)
    )
  end

  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  def handle_event("refresh_proxy_config", _value, socket) do
    config_module().clear_config_cache!()
    {:noreply, socket}
  end

  defp config_module, do: Application.fetch_env!(:unlock, :config_fetcher)

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
      ttl: resource.ttl
    }
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.SIRI{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier),
      original_url: resource.target_url,
      ttl: nil
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
      internal_count_default_value: nil
    }
  end

  defp extract_config(proxy_base_url, %Unlock.Config.Item.S3{} = resource) do
    %{
      unique_slug: resource.identifier,
      proxy_url: Transport.Proxy.resource_url(proxy_base_url, resource.identifier),
      # TODO: display original bucket & path name
      original_url: nil,
      ttl: resource.ttl
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

  defp add_cache_state(item) do
    cache_key = item.unique_slug |> Unlock.Shared.cache_key()
    cache_entry = cache_key |> Unlock.Shared.cache_entry()

    cache_ttl =
      case cache_key |> Unlock.Shared.cache_ttl() do
        {:ok, nil} ->
          "no ttl"

        {:ok, res_in_ms} ->
          in_seconds = res_in_ms / 1000
          "#{in_seconds |> Float.round() |> trunc()}s"
      end

    if cache_entry do
      Map.merge(item, %{
        cache_size: cache_entry.body |> byte_size() |> Sizeable.filesize(),
        cache_status: cache_entry.status,
        cache_ttl: cache_ttl
      })
    else
      item
    end
  end
end
