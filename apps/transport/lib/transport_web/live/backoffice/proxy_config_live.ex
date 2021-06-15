defmodule TransportWeb.Backoffice.ProxyConfigLive do
  @moduledoc """
  A view able to display the current running configuration of the proxy.

  It will soon support a hot-reload button, and caching stats.
  """
  use Phoenix.LiveView

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

  defp schedule_next_update_data() do
    Process.send_after(self(), :update_data, 250)
  end

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      proxy_configuration: get_proxy_configuration(socket.assigns.proxy_base_url)
    )
  end

  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  defp get_proxy_configuration(proxy_base_url) do
    data = Application.fetch_env!(:unlock, :config_fetcher).fetch_config!()

    data
    |> Map.values()
    |> Enum.sort_by(& &1.identifier)
    |> Enum.map(fn resource ->
      %{
        unique_slug: resource.identifier,
        proxy_url: get_proxy_resource_url(proxy_base_url, resource.identifier),
        original_url: resource.target_url,
        ttl: resource.ttl
      }
    end)
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
