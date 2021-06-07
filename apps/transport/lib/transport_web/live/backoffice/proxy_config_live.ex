defmodule TransportWeb.Backoffice.ProxyConfigLive do
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    socket = assign(socket, current_user: session["current_user"])

    # NOTE: this will have to be extracted as a shared module at next LV need
    # https://hexdocs.pm/phoenix_live_view/security-model.html
    # Also, disconnect will have to be handled:
    # https://hexdocs.pm/phoenix_live_view/security-model.html#disconnecting-all-instances-of-a-given-live-user
    socket =
      if (current_user = socket.assigns.current_user) &&
           TransportWeb.Router.is_transport_data_gouv_member?(current_user) do
        socket
      else
        redirect(socket, to: "/login")
      end

    socket = assign(socket, :proxy_configuration, get_proxy_configuration(session))
    {:ok, socket}
  end

  defp get_proxy_configuration(session) do
    config_method = Application.fetch_env!(:unlock, :resources)
    data = config_method.()
    # TODO: stop using an array here
    Enum.map(data, fn {slug, [resource]} ->
      %{
        unique_slug: slug,
        proxy_url: get_proxy_resource_url(session, slug),
        original_url: resource["url"],
        ttl: resource["ttl"]
      }
    end)
  end

  # Hackish stuff to create link to resource. To be replaced by
  # a cleaner and more explicit configuration later.
  def build_session(conn) do
    %{
      "current_user" => conn.assigns[:current_user],
      "proxy_base_url" =>
        TransportWeb.Router.Helpers.url(conn)
        |> String.replace("127.0.0.1", "localhost")
        |> String.replace("://", "://proxy.")
    }
  end

  defp get_proxy_resource_url(%{"proxy_base_url" => base_url}, slug) do
    Path.join(
      base_url,
      Unlock.Router.Helpers.resource_path(Unlock.Endpoint, :fetch, slug)
    )
  end
end
