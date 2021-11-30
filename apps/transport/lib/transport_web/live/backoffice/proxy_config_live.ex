defmodule TransportWeb.Backoffice.ProxyConfigLive do
  @moduledoc """
  A view able to display the current running configuration of the proxy.
  """
  use Phoenix.LiveView

  # The number of past days we want to report on (as a positive integer).
  # This is a DRYed ref we are using in multiple places.
  @stats_days 7

  # Authentication is assumed to happen in regular HTTP land. Here we verify
  # the user presence + belonging to admin team, or redirect immediately.
  def mount(_params, session, socket) do
    %{
      "current_user" => current_user,
      "proxy_base_url" => proxy_base_url
    } = session

    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket
       |> assign(proxy_base_url: proxy_base_url)
       |> update_data()
     end)}
  end

  #
  # If one calls "redirect" and does not leave immediately, the remaining code will
  # be executed, opening security issues. This method goal is to minimize this risk.
  # See https://hexdocs.pm/phoenix_live_view/security-model.html for overall docs.
  #
  # Also, disconnect will have to be handled:
  # https://hexdocs.pm/phoenix_live_view/security-model.html#disconnecting-all-instances-of-a-given-live-user
  #
  defp ensure_admin_auth_or_redirect(socket, current_user, func) do
    if current_user && TransportWeb.Router.is_transport_data_gouv_member?(current_user) do
      # We track down the current admin so that it can be used by next actions
      socket = assign(socket, current_admin_user: current_user)
      # Then call the remaining code, which is expected to return the socket
      func.(socket)
    else
      redirect(socket, to: "/login")
    end
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      stats_days: @stats_days,
      proxy_configuration: get_proxy_configuration(socket.assigns.proxy_base_url, @stats_days)
    )
  end

  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  def handle_event("refresh_proxy_config", _value, socket) do
    if socket.assigns.current_admin_user, do: config_module().clear_config_cache!()

    {:noreply, socket}
  end

  defp config_module, do: Application.fetch_env!(:unlock, :config_fetcher)

  defmodule Stats do
    @moduledoc """
    A quick stat module to compute the total count of event per identifier/event
    for the last N days
    """
    import Ecto.Query

    def compute(days) when days > 0 do
      date_from = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

      query =
        from(m in DB.Metrics,
          group_by: [m.target, m.event],
          where: m.period >= ^date_from,
          select: %{count: sum(m.count), identifier: m.target, event: m.event}
        )

      query |> DB.Repo.all()
    end
  end

  defp get_proxy_configuration(proxy_base_url, stats_days) do
    # NOTE: if the stats query becomes too costly, we will be able to throttle it every N seconds instead,
    # using a simple cache. At the moment, `get_proxy_configuration` is called once per frame, and not
    # once per item.
    stats =
      stats_days
      |> Stats.compute()
      |> Enum.group_by(fn x -> x[:identifier] end)
      |> Enum.into(%{}, fn {k, v} ->
        v = Enum.into(v, %{}, fn x -> {x[:event], x[:count]} end)
        {k, v}
      end)

    config_module().fetch_config!()
    |> Map.values()
    |> Enum.sort_by(& &1.identifier)
    |> Enum.map(fn resource ->
      %{
        unique_slug: resource.identifier,
        proxy_url: get_proxy_resource_url(proxy_base_url, resource.identifier),
        original_url: resource.target_url,
        ttl: resource.ttl
      }
      |> add_cache_state()
      |> add_stats(stats)
    end)
  end

  # a bit over the top, but this allows to keep events & database strings definitions in the telemetry module
  defp db_filter_for_event(type) do
    type
    |> Transport.Telemetry.proxy_request_event_name()
    |> Transport.Telemetry.database_event_name()
  end

  defp add_stats(item, stats) do
    metrics_target = Unlock.Controller.Telemetry.target_for_identifier(item.unique_slug)
    counts = stats[metrics_target] || %{}

    Map.merge(item, %{
      stats_external_requests: Map.get(counts, db_filter_for_event(:external), 0),
      stats_internal_requests: Map.get(counts, db_filter_for_event(:internal), 0)
    })
  end

  defp add_cache_state(item) do
    cache_entry =
      item.unique_slug
      |> Unlock.Shared.cache_key()
      |> Unlock.Shared.cache_entry()

    if cache_entry do
      Map.merge(item, %{
        cache_size: cache_entry.body |> byte_size() |> Sizeable.filesize(),
        cache_status: cache_entry.status
      })
    else
      item
    end
  end

  # This method is currently referenced in the proxy router, which
  # uses it to create initialisation data for the code to work (aka session)
  # It would be better to use a well-defined variable instead of this hack.
  def build_session(conn) do
    %{
      "current_user" => conn.assigns[:current_user],
      "proxy_base_url" =>
        conn
        |> TransportWeb.Router.Helpers.url()
        |> String.replace("127.0.0.1", "localhost")
        |> String.replace("://", "://proxy.")
    }
  end

  defp get_proxy_resource_url(proxy_base_url, slug) do
    Path.join(
      proxy_base_url,
      Unlock.Router.Helpers.resource_path(Unlock.Endpoint, :fetch, slug)
    )
  end
end
