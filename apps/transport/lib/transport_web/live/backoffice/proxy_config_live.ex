defmodule TransportWeb.Backoffice.ProxyConfigLive do
  @moduledoc """
  A view able to display the current running configuration of the proxy.

  It will soon support a hot-reload button, and caching stats.
  """
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    socket = assign(socket, current_user: session["current_user"])

    # NOTE: this will have to be extracted as a shared module at next LV need
    # https://hexdocs.pm/phoenix_live_view/security-model.html
    # Also, disconnect will have to be handled:
    # https://hexdocs.pm/phoenix_live_view/security-model.html#disconnecting-all-instances-of-a-given-live-user
    current_user = socket.assigns.current_user

    socket =
      if current_user &&
           TransportWeb.Router.is_transport_data_gouv_member?(current_user) do
        socket
      else
        redirect(socket, to: "/login")
      end

    socket = assign(socket, :proxy_configuration, get_proxy_configuration(session))
    {:ok, socket}
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

  # Hackish stuff to create link to resource. To be replaced by
  # a cleaner and more explicit configuration later.
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
