defmodule TransportWeb.Backoffice.GBFSLive do
  @moduledoc """
  A view able to display the current running configuration of the proxy.
  """
  use Phoenix.LiveView
  alias Transport.Telemetry
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.Router.Helpers

  @stats_days 7

  def mount(_params, session, socket) do
    %{"current_user" => current_user} = session

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
      stats: compute_stats(@stats_days)
    )
  end

  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  defp compute_stats(stats_days) do
    stats = DB.Metrics.for_last_days(stats_days, event_names())

    stats
    |> Map.keys()
    |> Enum.map(fn target ->
      %{
        target: target,
        network_name: target |> network_name()
      }
      |> add_stats(stats)
    end)
  end

  defp network_name(target) do
    target |> String.split(":") |> Enum.take(-1)
  end

  defp event_names do
    Telemetry.gbfs_request_event_names() |> Enum.map(&Telemetry.database_event_name/1)
  end

  defp db_filter_for_event(type) do
    type
    |> Telemetry.gbfs_request_event_name()
    |> Telemetry.database_event_name()
  end

  defp add_stats(item, stats) do
    counts = stats[item.target] || %{}

    Map.merge(item, %{
      stats_external_requests: Map.get(counts, db_filter_for_event(:external), 0),
      stats_internal_requests: Map.get(counts, db_filter_for_event(:internal), 0)
    })
  end

  def build_session(conn) do
    %{"current_user" => conn.assigns[:current_user]}
  end
end
