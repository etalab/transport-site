defmodule TransportWeb.Backoffice.ProxyConfigLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    # TODO: add auth https://hexdocs.pm/phoenix_live_view/security-model.html
    {:ok, assign(socket, :hello, "World")}
  end
end
