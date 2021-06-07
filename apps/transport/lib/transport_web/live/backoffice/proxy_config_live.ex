defmodule TransportWeb.Backoffice.ProxyConfigLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    # TODO: add auth https://hexdocs.pm/phoenix_live_view/security-model.html
    {:ok, assign(socket, :hello, "World")}
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

  end
end
