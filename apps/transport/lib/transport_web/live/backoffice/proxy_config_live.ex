defmodule TransportWeb.Backoffice.ProxyConfigLive do
  use Phoenix.LiveView

  def mount(_params, session, socket) do
    socket = assign(socket, :proxy_configuration, get_proxy_configuration(session))
    # TODO: add auth https://hexdocs.pm/phoenix_live_view/security-model.html
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
